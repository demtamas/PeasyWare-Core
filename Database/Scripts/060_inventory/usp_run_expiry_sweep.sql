USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/********************************************************************************************
    inventory.usp_run_expiry_sweep

    Flags every PTW/AV unit whose best_before_date has passed as EX (Expired).
    Deliberately a status change only - stock_state_code stays PTW, nothing
    physically moves. Query-time BBE comparisons elsewhere (e.g. allocation)
    are correct by construction regardless of whether this has run; this sweep
    exists to make expired stock VISIBLE (inventory/reporting, EX status,
    can_allocate=0 via stock_operation_rules) rather than to enforce eligibility -
    that enforcement is a separate, still-open piece of work.

    Unlike every other SP in this codebase, this one writes its own
    audit.trace_logs entry directly (INSERT, not via C#'s BuildResult) -
    it's called from a SQL Agent job step with no C# caller in the loop to
    do that logging the usual way, so it has to do it itself or the run
    is invisible in the Event Log entirely.

    Intended to run once daily via a SQL Agent job step, the same way the
    existing stuck-session cleanup job runs. Pass a fixed, real user_id for
    the job step - moved_by_user_id on inventory_movements is NOT NULL, so a
    genuine service/system account (not NULL) must be used.

    Contract:
      Result set 1: success BIT | result_code NVARCHAR(20) | expired_count INT
      Result set 2 (only if expired_count > 0): one row per unit flagged -
        inventory_unit_id | sscc | sku_code | best_before_date
********************************************************************************************/
CREATE OR ALTER PROCEDURE inventory.usp_run_expiry_sweep
(
    @user_id    INT              = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE @now   DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @today DATE         = CAST(@now AS DATE);

    DECLARE @expired_units TABLE
    (
        inventory_unit_id INT PRIMARY KEY,
        sku_id            INT,
        bin_id            INT
    );

    BEGIN TRY
        BEGIN TRAN;

        INSERT INTO @expired_units (inventory_unit_id, sku_id, bin_id)
        SELECT iu.inventory_unit_id, iu.sku_id, ip.bin_id
        FROM inventory.inventory_units iu WITH (UPDLOCK)
        JOIN inventory.inventory_placements ip
            ON ip.inventory_unit_id = iu.inventory_unit_id
        WHERE iu.stock_state_code   = 'PTW'
          AND iu.stock_status_code  = 'AV'
          AND iu.best_before_date IS NOT NULL
          AND iu.best_before_date  < @today;

        UPDATE iu
        SET iu.stock_status_code = 'EX',
            iu.updated_at        = @now,
            iu.updated_by        = @user_id
        FROM inventory.inventory_units iu
        JOIN @expired_units e ON e.inventory_unit_id = iu.inventory_unit_id;

        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id, sku_id, moved_qty,
            from_bin_id, to_bin_id,
            from_state_code, to_state_code,
            from_status_code, to_status_code,
            movement_type, reference_type, reference_id,
            moved_at, moved_by_user_id, session_id
        )
        SELECT
            e.inventory_unit_id, e.sku_id, iu.quantity,
            e.bin_id, e.bin_id,
            'PTW', 'PTW',
            'AV', 'EX',
            'STATUS_CHANGE', 'MANUAL', NULL,
            @now, @user_id, @session_id
        FROM @expired_units e
        JOIN inventory.inventory_units iu ON iu.inventory_unit_id = e.inventory_unit_id;

        COMMIT;

        DECLARE @expired_count INT = (SELECT COUNT(*) FROM @expired_units);

        -- Self-logged audit entry - see header comment for why this SP,
        -- alone among all of them, has to do this itself
        DECLARE @units_json NVARCHAR(MAX) = (
            SELECT
                e.inventory_unit_id                            AS InventoryUnitId,
                iu.external_ref                                AS Sscc,
                sk.sku_code                                     AS SkuCode,
                CONVERT(VARCHAR(10), iu.best_before_date, 23)  AS BestBeforeDate
            FROM @expired_units e
            JOIN inventory.inventory_units iu ON iu.inventory_unit_id = e.inventory_unit_id
            JOIN inventory.skus sk           ON sk.sku_id = iu.sku_id
            FOR JSON PATH
        );

        DECLARE @payload NVARCHAR(MAX) = (
            SELECT
                FORMAT(@now, 'yyyy-MM-ddTHH:mm:ss.fffZ') AS [Timestamp],
                N'INFO'                                   AS [Level],
                N'Inventory.ExpirySweep'                   AS [Action],
                JSON_QUERY((
                    SELECT
                        @user_id    AS UserId,
                        @session_id AS SessionId,
                        N'PeasyWare.SqlAgent' AS SourceApp,
                        N'SYSTEM'             AS SourceClient
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [Session],
                JSON_QUERY((
                    SELECT
                        @user_id       AS UserId,
                        N'SUCEXP01'    AS ResultCode,
                        CAST(1 AS BIT) AS Success,
                        JSON_QUERY((
                            SELECT
                                @expired_count AS ExpiredCount,
                                JSON_QUERY(ISNULL(@units_json, '[]')) AS ExpiredUnits
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS Outcome
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )) AS [Data]
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT INTO audit.trace_logs
            (occurred_at, correlation_id, user_id, session_id, level, action, payload_json)
        VALUES
            (@now, NEWID(), @user_id, @session_id, N'INFO', N'Inventory.ExpirySweep', @payload);

        SELECT
            CAST(1 AS BIT) AS success,
            N'SUCEXP01'    AS result_code,
            @expired_count AS expired_count;

        SELECT
            e.inventory_unit_id,
            iu.external_ref  AS sscc,
            sk.sku_code,
            iu.best_before_date
        FROM @expired_units e
        JOIN inventory.inventory_units iu ON iu.inventory_unit_id = e.inventory_unit_id
        JOIN inventory.skus sk           ON sk.sku_id = iu.sku_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;

        INSERT INTO audit.trace_logs
            (occurred_at, correlation_id, user_id, session_id, level, action, payload_json)
        VALUES
        (
            SYSUTCDATETIME(), NEWID(), @user_id, @session_id, N'ERROR', N'Inventory.ExpirySweep',
            (SELECT FORMAT(SYSUTCDATETIME(), 'yyyy-MM-ddTHH:mm:ss.fffZ') AS [Timestamp],
                    N'ERROR' AS [Level], N'Inventory.ExpirySweep' AS [Action],
                    ERROR_MESSAGE() AS [ErrorMessage]
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        );

        SELECT CAST(0 AS BIT) AS success, N'ERREXP99' AS result_code, 0 AS expired_count;
    END CATCH
END;
GO
