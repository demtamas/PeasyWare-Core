USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE warehouse.usp_bin_to_bin_move_confirm
(
    @task_id          INT,
    @scanned_bin_code NVARCHAR(100),
    @user_id          INT              = NULL,
    @session_id       UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        SET @scanned_bin_code = LTRIM(RTRIM(@scanned_bin_code)) COLLATE Latin1_General_CS_AS;

        DECLARE
            @inventory_unit_id  INT,
            @source_bin_id      INT,
            @destination_bin_id INT,
            @dest_bin_code      NVARCHAR(100),
            @task_state         VARCHAR(3),
            @sku_id             INT,
            @now                DATETIME2(3) = SYSUTCDATETIME();

        SELECT
            @inventory_unit_id  = inventory_unit_id,
            @source_bin_id      = source_bin_id,
            @destination_bin_id = destination_bin_id,
            @task_state         = task_state_code
        FROM warehouse.warehouse_tasks WITH (UPDLOCK, HOLDLOCK)
        WHERE task_id       = @task_id
          AND task_type_code = 'MOVE'
          AND task_state_code IN ('OPN', 'CLM');

        IF @inventory_unit_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE05' AS result_code;
            ROLLBACK; RETURN;
        END

        -- Validate scanned bin against destination
        SELECT @dest_bin_code = bin_code
        FROM locations.bins
        WHERE bin_id = @destination_bin_id;

        IF @dest_bin_code IS NOT NULL
           AND LTRIM(RTRIM(@scanned_bin_code)) <> LTRIM(RTRIM(@dest_bin_code))
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRMOVE06' AS result_code;
            ROLLBACK; RETURN;
        END

        -- If no destination was set on the task, resolve the scanned bin
        IF @destination_bin_id IS NULL
        BEGIN
            SELECT @destination_bin_id = bin_id
            FROM locations.bins
            WHERE bin_code = @scanned_bin_code COLLATE Latin1_General_CS_AS AND is_active = 1;

            IF @destination_bin_id IS NULL
            BEGIN
                SELECT CAST(0 AS BIT) AS success, N'ERRMOVE04' AS result_code;
                ROLLBACK; RETURN;
            END

            SET @dest_bin_code = @scanned_bin_code COLLATE Latin1_General_CS_AS;
        END

        SELECT @sku_id = sku_id FROM inventory.inventory_units WHERE inventory_unit_id = @inventory_unit_id;

        -- Update placement
        UPDATE inventory.inventory_placements
        SET bin_id = @destination_bin_id
        WHERE inventory_unit_id = @inventory_unit_id;

        -- Record movement
        DECLARE @movement_id INT;

        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty,
             from_bin_id, to_bin_id,
             from_state_code, to_state_code,
             from_status_code, to_status_code,
             movement_type, reference_type, reference_id,
             moved_at, moved_by_user_id, session_id)
        SELECT
            @inventory_unit_id, @sku_id, quantity,
            @source_bin_id, @destination_bin_id,
            stock_state_code, stock_state_code,  -- PTW->PTW, state unchanged during move
            stock_status_code, stock_status_code,
            'MOVE', 'TASK', @task_id,
            @now, @user_id, @session_id
        FROM inventory.inventory_units
        WHERE inventory_unit_id = @inventory_unit_id;

        -- Complete task
        UPDATE warehouse.warehouse_tasks
        SET task_state_code      = 'CNF',
            completed_at         = @now,
            completed_by_user_id = @user_id,
            updated_at           = @now,
            updated_by           = @user_id
        WHERE task_id = @task_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCMOVE02' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRMOVE99' AS result_code;
    END CATCH
END;
GO
PRINT 'warehouse.usp_bin_to_bin_move_confirm created.';
GO

PRINT '------------------------------------------------------------';
PRINT 'Bin-to-bin move SPs complete.';
PRINT '------------------------------------------------------------';
GO

-- ── Fix: usp_putaway_confirm_task stock state comment correction ────────────────
-- PTW = PUTAWAY (final racked state, not "in progress" as previously assumed).
-- The confirm SP was already setting PTW correctly.
-- The real issue was that usp_bin_to_bin_move_create was rejecting PTW state.
-- Fix: allow PTW in the move create SP (already done above).
-- This SP rewrite is retained to fix the from_state_code in the movement record
-- (was recording RCD->PTW but should be PTW->PTW for a putaway confirm).


-- ============================================================
-- inventory.v_skus + usp_update_sku
-- Merged from WIP: 2026-05-09
-- ============================================================

-- ── v_skus ────────────────────────────────────────────────────────────────────
GO
