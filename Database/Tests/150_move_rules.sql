-- ==========================================================
-- TEST: Bin-to-bin move rules
--
-- Covers the two shared rules (warehouse.fn_unit_move_block_code,
-- warehouse.fn_bin_receive_block_code) directly, then the move
-- procedures end to end:
--
--   Rules:   free unit passes; blocked (BL) stock IS movable (e.g. out
--            to quarantine); non-movable state (PKD) refused; unit with
--            an open task refused (unless it is the caller's own); the
--            data-driven can_move = 0 rule refused (via a temporary
--            rule row, rolled back); bin: free passes, full / locked /
--            inactive / missing refused
--   Create:  task + MOVE reservation created; a second move into
--            the same capacity-1 bin is refused while it is held;
--            full / locked / inactive / missing / same bin / non-movable
--            unit / unit with open task all refused with NO task and
--            NO reservation left behind; blocked stock gets a task
--   Confirm: placement moves, task CNF, reservation released, ledger
--            row written, bin now reports full
--   Stale:   a MOVE task past its TTL is expired and replaced, its
--            reservation released
--   Guards:  confirm refuses if the unit was relocated, or became
--            non-movable (picked), after the task was created - and
--            changes nothing
--
-- No outer transaction: the procedures ROLLBACK internally on their
-- refusal paths, so (as in 146) fixtures are cleaned up explicitly.
-- Refusals are asserted by their side effects (no task, no
-- reservation, placement unchanged) and by the rule functions, which
-- return the exact code.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous aborted run.
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'MVTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'MVTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'MVTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'MVTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'MVTEST-%';
DELETE FROM inventory.skus            WHERE sku_code = 'MVTEST-SKU';
DELETE FROM locations.bins            WHERE bin_code LIKE 'MVTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code = 'MVTEST-STYPE';
GO

DECLARE @err NVARCHAR(2048) = NULL;

BEGIN TRY

    DECLARE @UserId INT = (SELECT TOP (1) id FROM auth.users WHERE username = 'system');
    IF @UserId IS NULL
        RAISERROR('TEST SETUP FAILED: system user not found.', 16, 1);

    ----------------------------------------------------------------
    -- Fixture
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name)
    VALUES ('MVTEST-STYPE', 'Move Test Type');
    DECLARE @StypeId INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'MVTEST-STYPE');

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked) VALUES
        ('MVTEST-SRC',   @StypeId, 999, 1, 0),
        ('MVTEST-ALT',   @StypeId, 999, 1, 0),
        ('MVTEST-D1',    @StypeId, 1,   1, 0),
        ('MVTEST-FULL',  @StypeId, 1,   1, 0),
        ('MVTEST-LOCK',  @StypeId, 1,   1, 1),
        ('MVTEST-INACT', @StypeId, 1,   0, 0),
        ('MVTEST-D2',    @StypeId, 1,   1, 0),
        ('MVTEST-D3',    @StypeId, 1,   1, 0),
        ('MVTEST-D4',    @StypeId, 1,   1, 0),
        ('MVTEST-D5',    @StypeId, 1,   1, 0),
        ('MVTEST-D6',    @StypeId, 1,   1, 0);

    DECLARE @BSrc   INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-SRC');
    DECLARE @BAlt   INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-ALT');
    DECLARE @BD1    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-D1');
    DECLARE @BFull  INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-FULL');
    DECLARE @BLock  INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-LOCK');
    DECLARE @BInact INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-INACT');
    DECLARE @BD2    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-D2');
    DECLARE @BD3    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-D3');
    DECLARE @BD4    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-D4');
    DECLARE @BD5    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-D5');
    DECLARE @BD6    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'MVTEST-D6');

    INSERT INTO inventory.skus (sku_code, sku_description, uom_code, preferred_storage_type_id)
    VALUES ('MVTEST-SKU', 'Move Test SKU', 'EA', @StypeId);
    DECLARE @SkuId INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'MVTEST-SKU');

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code) VALUES
        (@SkuId, 'MVTEST-U1',     10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-U2',     10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-U3',     10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-UBLK',   10, 'PTW', 'BL'),
        (@SkuId, 'MVTEST-UDM',    10, 'PTW', 'DM'),
        (@SkuId, 'MVTEST-UPK',    10, 'PKD', 'AV'),
        (@SkuId, 'MVTEST-UPICK',  10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-USTALE', 10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-URELOC', 10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-USTAT',  10, 'PTW', 'AV'),
        (@SkuId, 'MVTEST-UFULL',  10, 'PTW', 'AV');

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    SELECT u.inventory_unit_id,
           CASE WHEN u.external_ref = 'MVTEST-UFULL' THEN @BFull ELSE @BSrc END
    FROM inventory.inventory_units u
    WHERE u.external_ref LIKE 'MVTEST-%';

    DECLARE @U1     INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-U1');
    DECLARE @U2     INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-U2');
    DECLARE @U3     INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-U3');
    DECLARE @UBlk   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-UBLK');
    DECLARE @UDm    INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-UDM');
    DECLARE @UPk    INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-UPK');
    DECLARE @UPick  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-UPICK');
    DECLARE @UStale INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-USTALE');
    DECLARE @UReloc INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-URELOC');
    DECLARE @UStat  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'MVTEST-USTAT');

    -- UPICK has an open PICK task: it must not be movable
    INSERT INTO warehouse.warehouse_tasks
        (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id,
         task_state_code, expires_at, created_by)
    VALUES
        ('PICK', @UPick, @BSrc, @BAlt, 'OPN', DATEADD(MINUTE, 5, SYSUTCDATETIME()), @UserId);
    DECLARE @PickTaskId INT = SCOPE_IDENTITY();

    ----------------------------------------------------------------
    -- 1. Shared rule: unit
    ----------------------------------------------------------------
    IF warehouse.fn_unit_move_block_code(@U1, NULL) IS NOT NULL
        RAISERROR('FAIL: a free PTW/AV unit was reported as not movable.', 16, 1);

    IF warehouse.fn_unit_move_block_code(@UBlk, NULL) IS NOT NULL
        RAISERROR('FAIL: blocked-status (BL) stock must be movable (e.g. out to quarantine).', 16, 1);

    IF ISNULL(warehouse.fn_unit_move_block_code(@UPk, NULL), '') <> 'ERRMOVE02'
        RAISERROR('FAIL: picked (PKD) unit was not refused with ERRMOVE02.', 16, 1);

    IF ISNULL(warehouse.fn_unit_move_block_code(@UPick, NULL), '') <> 'ERRMOVE10'
        RAISERROR('FAIL: unit with an open task was not refused with ERRMOVE10.', 16, 1);

    IF warehouse.fn_unit_move_block_code(@UPick, @PickTaskId) IS NOT NULL
        RAISERROR('FAIL: ignoring the unit''s own open task should leave it movable.', 16, 1);

    -- Data-driven rule: with no rule row a DM unit is movable; with a
    -- can_move = 0 row it is refused with ERRMOVE08. The row is temporary
    -- and rolled back (function calls only here - no procedure that
    -- rolls back internally runs inside this transaction).
    IF warehouse.fn_unit_move_block_code(@UDm, NULL) IS NOT NULL
        RAISERROR('FAIL: a unit with no stock_operation_rules row should be movable.', 16, 1);

    BEGIN TRAN;

        INSERT INTO inventory.stock_operation_rules
            (state_code, status_code, can_move, can_allocate, can_ship, can_adjust, requires_override)
        VALUES ('PTW', 'DM', 0, 0, 0, 0, 0);

        IF ISNULL(warehouse.fn_unit_move_block_code(@UDm, NULL), '') <> 'ERRMOVE08'
            RAISERROR('FAIL: a can_move = 0 rule did not refuse the unit with ERRMOVE08.', 16, 1);

    ROLLBACK;

    PRINT 'PASS: unit rule (free / blocked stock movable / non-movable state / open task / can_move = 0 rule).';

    ----------------------------------------------------------------
    -- 2. Shared rule: bin
    ----------------------------------------------------------------
    IF warehouse.fn_bin_receive_block_code(@BD1) IS NOT NULL
        RAISERROR('FAIL: a free capacity-1 bin was reported as unable to receive.', 16, 1);

    IF ISNULL(warehouse.fn_bin_receive_block_code(@BFull), '') <> 'ERRMOVE09'
        RAISERROR('FAIL: full bin was not refused with ERRMOVE09.', 16, 1);

    IF ISNULL(warehouse.fn_bin_receive_block_code(@BLock), '') <> 'ERRMOVE07'
        RAISERROR('FAIL: locked bin was not refused with ERRMOVE07.', 16, 1);

    IF ISNULL(warehouse.fn_bin_receive_block_code(@BInact), '') <> 'ERRMOVE07'
        RAISERROR('FAIL: inactive bin was not refused with ERRMOVE07.', 16, 1);

    IF ISNULL(warehouse.fn_bin_receive_block_code(-1), '') <> 'ERRMOVE04'
        RAISERROR('FAIL: missing bin was not refused with ERRMOVE04.', 16, 1);

    PRINT 'PASS: bin rule (free / full / locked / inactive / missing).';

    ----------------------------------------------------------------
    -- 3. Create: task + reservation, and the slot is held
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-U1', @destination_bin_code = 'MVTEST-D1', @user_id = @UserId;

    DECLARE @Task1 INT = (SELECT TOP (1) task_id FROM warehouse.warehouse_tasks
                          WHERE inventory_unit_id = @U1 AND task_type_code = 'MOVE'
                            AND task_state_code IN ('OPN', 'CLM'));
    IF @Task1 IS NULL
        RAISERROR('FAIL: move create did not produce an open MOVE task for a free unit.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bin_reservations
                   WHERE task_id = @Task1 AND bin_id = @BD1 AND reservation_type = 'MOVE')
        RAISERROR('FAIL: move create did not reserve the destination bin for its task.', 16, 1);

    -- A different unit heading for the same capacity-1 bin must be refused
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-U2', @destination_bin_code = 'MVTEST-D1', @user_id = @UserId;

    IF EXISTS (SELECT 1 FROM warehouse.warehouse_tasks
               WHERE inventory_unit_id = @U2 AND task_state_code IN ('OPN', 'CLM'))
        RAISERROR('FAIL: a second move into a bin already held by an open move was accepted.', 16, 1);

    PRINT 'PASS: create makes task + reservation, and the held slot refuses a competitor.';

    ----------------------------------------------------------------
    -- 4. Create: refusals leave nothing behind
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-U3', @destination_bin_code = 'MVTEST-FULL',  @user_id = @UserId;
    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-U3', @destination_bin_code = 'MVTEST-LOCK',  @user_id = @UserId;
    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-U3', @destination_bin_code = 'MVTEST-INACT', @user_id = @UserId;
    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-U3', @destination_bin_code = 'MVTEST-SRC',   @user_id = @UserId;
    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-U3', @destination_bin_code = 'MVTEST-NOPE',  @user_id = @UserId;

    IF EXISTS (SELECT 1 FROM warehouse.warehouse_tasks
               WHERE inventory_unit_id = @U3 AND task_state_code IN ('OPN', 'CLM'))
        RAISERROR('FAIL: a move into a full / locked / inactive / same / missing bin created a task.', 16, 1);

    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-UPK', @destination_bin_code = 'MVTEST-D2', @user_id = @UserId;
    EXEC warehouse.usp_bin_to_bin_move_create @external_ref = 'MVTEST-UPICK', @destination_bin_code = 'MVTEST-D2', @user_id = @UserId;

    IF EXISTS (SELECT 1 FROM warehouse.warehouse_tasks
               WHERE inventory_unit_id = @UPk AND task_state_code IN ('OPN', 'CLM'))
        RAISERROR('FAIL: a non-movable (picked) unit got a move task.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @UPick AND task_state_code IN ('OPN', 'CLM')) <> 1
        RAISERROR('FAIL: a unit with an open PICK task gained a second open task.', 16, 1);

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE bin_id = @BD2)
        RAISERROR('FAIL: a refused move left a reservation behind on the destination bin.', 16, 1);

    PRINT 'PASS: every refusal leaves no task and no reservation.';

    ----------------------------------------------------------------
    -- 4b. Blocked stock can be moved (e.g. out to quarantine)
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-UBLK', @destination_bin_code = 'MVTEST-D6', @user_id = @UserId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.warehouse_tasks
                   WHERE inventory_unit_id = @UBlk AND task_type_code = 'MOVE'
                     AND task_state_code IN ('OPN', 'CLM'))
        RAISERROR('FAIL: blocked (BL) stock was refused a move.', 16, 1);

    PRINT 'PASS: blocked stock can be moved.';

    ----------------------------------------------------------------
    -- 5. Confirm: apply, release the hold, write the ledger
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_confirm
        @task_id = @Task1, @scanned_bin_code = 'MVTEST-D1', @user_id = @UserId;

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @U1) <> @BD1
        RAISERROR('FAIL: confirm did not move the placement to the destination bin.', 16, 1);

    IF (SELECT task_state_code FROM warehouse.warehouse_tasks WHERE task_id = @Task1) <> 'CNF'
        RAISERROR('FAIL: confirm did not complete the task.', 16, 1);

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE task_id = @Task1)
        RAISERROR('FAIL: confirm did not release the task''s reservation.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_movements
                   WHERE inventory_unit_id = @U1 AND from_bin_id = @BSrc AND to_bin_id = @BD1
                     AND movement_type = 'MOVE')
        RAISERROR('FAIL: confirm did not write the MOVE ledger row.', 16, 1);

    IF ISNULL(warehouse.fn_bin_receive_block_code(@BD1), '') <> 'ERRMOVE09'
        RAISERROR('FAIL: after confirm the destination bin should report full.', 16, 1);

    PRINT 'PASS: confirm applies the move, releases the hold, writes the ledger.';

    ----------------------------------------------------------------
    -- 6. Stale task: expired and replaced, reservation released
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-USTALE', @destination_bin_code = 'MVTEST-D2', @user_id = @UserId;

    DECLARE @StaleOld INT = (SELECT TOP (1) task_id FROM warehouse.warehouse_tasks
                             WHERE inventory_unit_id = @UStale AND task_type_code = 'MOVE'
                               AND task_state_code IN ('OPN', 'CLM'));
    IF @StaleOld IS NULL
        RAISERROR('FAIL (setup): stale-task fixture move was not created.', 16, 1);

    UPDATE warehouse.warehouse_tasks
    SET expires_at = DATEADD(MINUTE, -1, SYSUTCDATETIME())
    WHERE task_id = @StaleOld;

    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-USTALE', @destination_bin_code = 'MVTEST-D3', @user_id = @UserId;

    IF (SELECT task_state_code FROM warehouse.warehouse_tasks WHERE task_id = @StaleOld) <> 'EXP'
        RAISERROR('FAIL: the expired MOVE task was not marked EXP.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.warehouse_tasks
        WHERE inventory_unit_id = @UStale AND task_state_code IN ('OPN', 'CLM')) <> 1
        RAISERROR('FAIL: expected exactly one open task after replacing a stale one.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.warehouse_tasks
                   WHERE inventory_unit_id = @UStale AND task_state_code = 'OPN'
                     AND destination_bin_id = @BD3)
        RAISERROR('FAIL: the replacement task does not point at the new destination.', 16, 1);

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE bin_id = @BD2)
        RAISERROR('FAIL: the stale task''s reservation was not released.', 16, 1);

    PRINT 'PASS: stale MOVE task expired, replaced, reservation released.';

    ----------------------------------------------------------------
    -- 7. Confirm guard: unit relocated after the task was created
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-URELOC', @destination_bin_code = 'MVTEST-D4', @user_id = @UserId;

    DECLARE @TaskReloc INT = (SELECT TOP (1) task_id FROM warehouse.warehouse_tasks
                              WHERE inventory_unit_id = @UReloc AND task_state_code IN ('OPN', 'CLM'));

    UPDATE inventory.inventory_placements SET bin_id = @BAlt WHERE inventory_unit_id = @UReloc;

    EXEC warehouse.usp_bin_to_bin_move_confirm
        @task_id = @TaskReloc, @scanned_bin_code = 'MVTEST-D4', @user_id = @UserId;

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UReloc) <> @BAlt
        RAISERROR('FAIL: confirm moved a unit that had been relocated since the task was created.', 16, 1);

    IF (SELECT task_state_code FROM warehouse.warehouse_tasks WHERE task_id = @TaskReloc) NOT IN ('OPN', 'CLM')
        RAISERROR('FAIL: a refused confirm should leave the task open.', 16, 1);

    PRINT 'PASS: confirm refuses a unit relocated since create.';

    ----------------------------------------------------------------
    -- 8. Confirm guard: unit became non-movable (picked) after the task was created
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'MVTEST-USTAT', @destination_bin_code = 'MVTEST-D5', @user_id = @UserId;

    DECLARE @TaskStat INT = (SELECT TOP (1) task_id FROM warehouse.warehouse_tasks
                             WHERE inventory_unit_id = @UStat AND task_state_code IN ('OPN', 'CLM'));

    UPDATE inventory.inventory_units SET stock_state_code = 'PKD' WHERE inventory_unit_id = @UStat;

    EXEC warehouse.usp_bin_to_bin_move_confirm
        @task_id = @TaskStat, @scanned_bin_code = 'MVTEST-D5', @user_id = @UserId;

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UStat) <> @BSrc
        RAISERROR('FAIL: confirm moved a unit that became non-movable after the task was created.', 16, 1);

    PRINT 'PASS: confirm refuses a unit made non-movable since create.';

    PRINT 'TEST PASSED: bin-to-bin move rules.';

END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH

-- Cleanup (always runs)
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'MVTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'MVTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'MVTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'MVTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'MVTEST-%';
DELETE FROM inventory.skus            WHERE sku_code = 'MVTEST-SKU';
DELETE FROM locations.bins            WHERE bin_code LIKE 'MVTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code = 'MVTEST-STYPE';

IF @err IS NOT NULL
    RAISERROR(@err, 16, 1);
GO
