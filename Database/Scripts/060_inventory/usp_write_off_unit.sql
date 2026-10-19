USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/********************************************************************************************
    inventory.usp_write_off_unit

    Writes off a single unit: clears its placement, transitions it to the
    terminal SCR (Scrapped) state, and records an ADJUSTMENT movement.

    This is the foundation only - one unit, one call, no scrap-order
    workflow, no scrap staging area. Deliberately scoped this way; a
    documented Disposal Order process (scrap-yard party, generated note,
    its own lifecycle) is a separate, larger piece of future work sitting
    on top of this primitive, not part of it.

    Eligible statuses are held in a short explicit list rather than a
    single comparison, so widening this later (DM, long-stuck BL) is a
    one-line change here, not a rewrite. Only PTW/RCD units are handled -
    anything already mid-flow (picked, loaded, in movement) needs its own
    path and is deliberately rejected here rather than silently accepted.

    Contract: success BIT | result_code NVARCHAR(20)
              | inventory_unit_id INT | sku_id INT | reason NVARCHAR(200)
********************************************************************************************/
CREATE OR ALTER PROCEDURE inventory.usp_write_off_unit
(
    @inventory_unit_id INT,
    @reason            NVARCHAR(200)    = NULL,
    @user_id           INT              = NULL,
    @session_id        UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @current_state  VARCHAR(3),
        @current_status VARCHAR(2),
        @sku_id         INT,
        @quantity       INT,
        @from_bin_id    INT,
        @now            DATETIME2(3) = SYSUTCDATETIME();

    DECLARE @eligible_statuses TABLE (status_code VARCHAR(2) PRIMARY KEY);
    INSERT INTO @eligible_statuses VALUES ('EX');

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @current_state  = iu.stock_state_code,
            @current_status = iu.stock_status_code,
            @sku_id         = iu.sku_id,
            @quantity       = iu.quantity
        FROM inventory.inventory_units iu WITH (UPDLOCK, HOLDLOCK)
        WHERE iu.inventory_unit_id = @inventory_unit_id;

        IF @current_state IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSCR01' AS result_code,
                   NULL AS inventory_unit_id, NULL AS sku_id, @reason AS reason;
            ROLLBACK; RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM @eligible_statuses WHERE status_code = @current_status)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSCR02' AS result_code,
                   @inventory_unit_id AS inventory_unit_id, @sku_id AS sku_id, @reason AS reason;
            ROLLBACK; RETURN;
        END

        IF @current_state NOT IN ('PTW', 'RCD')
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSCR03' AS result_code,
                   @inventory_unit_id AS inventory_unit_id, @sku_id AS sku_id, @reason AS reason;
            ROLLBACK; RETURN;
        END

        -- The effect itself (placement removed, state to SCR, ledger row) lives in
        -- one place, shared with the stock-count adjustment.
        DECLARE @movement_id INT;

        EXEC inventory.usp_apply_scrap
            @inventory_unit_id = @inventory_unit_id,
            @reference_type    = N'MANUAL',
            @reference_id      = NULL,
            @user_id           = @user_id,
            @session_id        = @session_id,
            @movement_id       = @movement_id OUTPUT;

        COMMIT;

        SELECT
            CAST(1 AS BIT)     AS success,
            N'SUCSCR01'        AS result_code,
            @inventory_unit_id AS inventory_unit_id,
            @sku_id            AS sku_id,
            @reason            AS reason;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSCR99' AS result_code,
               @inventory_unit_id AS inventory_unit_id, NULL AS sku_id, @reason AS reason;
    END CATCH
END;
GO
