USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- Deactivate bin (soft delete)
-- Blocked if: has active stock OR open warehouse tasks
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_deactivate_bin
(
    @bin_code       NVARCHAR(100),
    @reason         NVARCHAR(255)    = NULL,
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @bin_id INT;

        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS;

        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_id = @bin_id AND is_active = 0)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN08' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Block if stock present
        IF EXISTS (
            SELECT 1
            FROM inventory.inventory_placements ip
            JOIN inventory.inventory_units iu
                ON iu.inventory_unit_id = ip.inventory_unit_id
               AND iu.stock_state_code NOT IN ('SHP', 'REV')
            WHERE ip.bin_id = @bin_id
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN09' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Block if open warehouse tasks assigned to this bin
        IF EXISTS (
            SELECT 1
            FROM warehouse.warehouse_tasks
            WHERE (source_bin_id = @bin_id OR destination_bin_id = @bin_id)
              AND task_state_code NOT IN ('CNF', 'CNL', 'EXP')
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN10' AS result_code;
            ROLLBACK; RETURN;
        END

        UPDATE locations.bins
        SET is_active  = 0,
            notes      = CASE
                            WHEN @reason IS NOT NULL
                            THEN ISNULL(notes + ' | ', '') + 'Deactivated: ' + @reason
                            ELSE notes
                         END,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        WHERE bin_id = @bin_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN06' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code;
    END CATCH
END;
GO

-- ============================================================
-- Reactivate bin
-- ============================================================

CREATE OR ALTER PROCEDURE locations.usp_reactivate_bin
(
    @bin_code       NVARCHAR(100),
    @user_id        INT              = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @correlation_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @bin_id INT;

        SELECT @bin_id = bin_id
        FROM locations.bins WITH (UPDLOCK, HOLDLOCK)
        WHERE bin_code = @bin_code COLLATE Latin1_General_CS_AS;

        IF @bin_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN01' AS result_code;
            ROLLBACK; RETURN;
        END

        IF EXISTS (SELECT 1 FROM locations.bins WHERE bin_id = @bin_id AND is_active = 1)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRBIN11' AS result_code;
            ROLLBACK; RETURN;
        END

        UPDATE locations.bins
        SET is_active  = 1,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        WHERE bin_id = @bin_id;

        COMMIT;
        SELECT CAST(1 AS BIT) AS success, N'SUCBIN07' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRBIN99' AS result_code;
    END CATCH
END;
GO
