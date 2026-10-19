-- ==========================================================
-- TEST: Bin count (BIN_COUNT) - blind count of the stock in occupied bins
--
--   Start:    snapshots exactly the active bins that hold stock (an empty
--             bin and an inactive bin are excluded); starting again RESUMES;
--             a storage type that does not exist starts nothing; a single
--             storage type may run beside another, but not beside a sweep
--   Open:     scanning the bin takes a COUNT hold (a reservation tied to the
--             count line); a bin not in the count, or in the wrong case,
--             changes nothing; a bin with an open task or another reservation
--             is refused (work in progress)
--   Lock:     while a bin is held, nothing may go into it (receive rule), no
--             unit may leave it (move rule), a move into / out of it creates
--             no task, putaway never suggests it, and picking from it is
--             refused; an EXPIRED hold locks nothing; once the bin is
--             finished all of that works again
--   Scan:     blind - a scan before the bin is open, a quantity of 0 and a
--             blank SSCC are refused; a quantity that differs from the system's
--             for a pallet recorded in THIS bin is not recorded until the
--             operator confirms it; scanning again replaces the quantity;
--             a pallet recorded elsewhere, unknown or shipped is simply
--             recorded (no prompt, nothing disclosed); an expired hold refuses
--             the scan, and re-opening the bin resumes with the scans kept
--   Finish:   every difference is a finding - QTY_DIFFERENCE (counted vs
--             system), MISSING, MISPLACED, UNKNOWN_UNIT, NOT_CORRECTED
--             (shipped, ERRCNT06) - and NO stock record is changed; the hold
--             is released; a bin where everything agrees is MATCHED; the same
--             bin cannot be finished twice
--   Safeguard: if the movement ledger shows a movement to or from the bin
--             since it was opened, finish records nothing, clears the scans
--             and sends the bin back to PENDING to be counted again
--   Cancel:   discards the scans, releases the hold, back to PENDING
--   Close:    refused while a bin is still open; REVIEW when unresolved
--             findings exist; CLOSED when bins remain and nothing to review
--   Sweep:    no storage type = every storage type; resumes; refuses a
--             single-storage-type count beside it
--   Guards:   the empty-bin procedures refuse a bin count and vice versa
--   Ad hoc:   a hand-picked list of bins (any active bin, empty or occupied) is a
--             count of its own: an empty / inactive / unknown / wrong-case list
--             starts nothing; a bin named twice is one line; it runs beside a
--             sweep and beside another ad hoc count; an empty bin counted with
--             nothing scanned is MATCHED, and a pallet found in one is a finding
--   Anyone:   every counting call is made by an OPERATOR-role user
--
-- No outer transaction: the procedures roll back internally on their
-- refusal paths, so (as in 146 / 150 / 160) fixtures are cleaned explicitly.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous aborted run.
DELETE f FROM warehouse.count_findings f
    JOIN warehouse.count_lines l    ON l.count_line_id = f.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE sc FROM warehouse.count_scans sc
    JOIN warehouse.count_lines l    ON l.count_line_id = sc.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE l FROM warehouse.count_lines l
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE s FROM warehouse.count_sessions s
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'BINTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'BINTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'BINTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'BINTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'BINTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'BINTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'BINTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'BINTEST-%';
DELETE ur FROM auth.user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.username LIKE 'bintest[_]%';
DELETE FROM auth.users                WHERE username LIKE 'bintest[_]%';
GO

-- A real OPEN bin count would be resumed (or would block a sweep) and this test
-- would then be operating on someone's live count. Don't: skip, and say why.
IF EXISTS (SELECT 1 FROM warehouse.count_sessions WHERE count_type_code = 'BIN_COUNT' AND status_code = 'OPEN')
BEGIN
    PRINT 'SKIPPED: an OPEN bin count already exists in this database. Close it, then run this test again.';
    RETURN;   -- same batch as the test below, so this really does skip it
END

DECLARE @err NVARCHAR(2048) = NULL;

BEGIN TRY

    DECLARE @UserId INT = (SELECT TOP (1) id FROM auth.users WHERE username = 'system');
    IF @UserId IS NULL
        RAISERROR('TEST SETUP FAILED: system user not found.', 16, 1);

    ----------------------------------------------------------------
    -- Fixture
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name) VALUES
        ('BINTEST-A', 'Bin Count Test A'),
        ('BINTEST-B', 'Bin Count Test B'),
        ('BINTEST-C', 'Bin Count Test C');

    DECLARE @StA INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'BINTEST-A');
    DECLARE @StB INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'BINTEST-B');
    DECLARE @StC INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'BINTEST-C');

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked) VALUES
        ('BINTEST-A1', @StA, 4, 1, 0),   -- the difference bin: U1 U2 U9
        ('BINTEST-A2', @StA, 4, 1, 0),   -- the clean bin: U3
        ('BINTEST-A3', @StA, 4, 1, 0),   -- the bin that changes under the count: U4
        ('BINTEST-A4', @StA, 4, 1, 0),   -- empty: not in a bin count
        ('BINTEST-A5', @StA, 4, 0, 0),   -- inactive, holds stock: not in a bin count
        ('BINTEST-A6', @StA, 4, 1, 0),   -- holds U6 (found "misplaced" in A1)
        ('BINTEST-B1', @StB, 4, 1, 0),
        ('BINTEST-C1', @StC, 5, 1, 0);

    DECLARE @A1 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-A1');
    DECLARE @A2 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-A2');
    DECLARE @A3 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-A3');
    DECLARE @A4 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-A4');
    DECLARE @A5 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-A5');
    DECLARE @A6 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-A6');
    DECLARE @B1 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-B1');
    DECLARE @C1 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'BINTEST-C1');

    INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, preferred_storage_type_id) VALUES
        ('BINTEST-SKU',   'Bin Count Test SKU',   '09999900001811', 'EA', @StA),
        ('BINTEST-SKU-C', 'Bin Count Test SKU C', '09999900001812', 'EA', @StC);

    DECLARE @SkuId  INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'BINTEST-SKU');
    DECLARE @SkuCId INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'BINTEST-SKU-C');

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code) VALUES
        (@SkuId,  'BINTEST-U1',   10, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U2',   20, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U9',   90, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U3',   30, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U4',   40, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U6',   60, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U5',   50, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-U10',  10, 'PTW', 'AV'),
        (@SkuId,  'BINTEST-USHP', 10, 'SHP', 'AV'),
        (@SkuCId, 'BINTEST-U7',   70, 'PTW', 'AV'),
        (@SkuCId, 'BINTEST-UNEW', 10, 'RCD', 'AV');

    DECLARE @U1   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-U1');
    DECLARE @U2   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-U2');
    DECLARE @U9   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-U9');
    DECLARE @U3   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-U3');
    DECLARE @U4   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-U4');
    DECLARE @U6   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-U6');
    DECLARE @UNew INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'BINTEST-UNEW');

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    SELECT u.inventory_unit_id,
           CASE u.external_ref
                WHEN 'BINTEST-U1'  THEN @A1
                WHEN 'BINTEST-U2'  THEN @A1
                WHEN 'BINTEST-U9'  THEN @A1
                WHEN 'BINTEST-U3'  THEN @A2
                WHEN 'BINTEST-U4'  THEN @A3
                WHEN 'BINTEST-U6'  THEN @A6
                WHEN 'BINTEST-U5'  THEN @B1
                WHEN 'BINTEST-U10' THEN @A5
                WHEN 'BINTEST-U7'  THEN @C1
           END
    FROM inventory.inventory_units u
    WHERE u.external_ref LIKE 'BINTEST-%'
      AND u.external_ref NOT IN ('BINTEST-USHP', 'BINTEST-UNEW');   -- shipped / unplaced: no placement

    -- The counter: an OPERATOR. Counting must not need more than that.
    DECLARE @OpRole INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    IF @OpRole IS NULL
        RAISERROR('TEST SETUP FAILED: operator role not found.', 16, 1);

    INSERT INTO auth.users (username, display_name, email, salt, is_active)
    VALUES ('bintest_operator', 'Bin Count Test Operator (temp)', 'bintest_operator@pw.local', 0x00, 1);

    DECLARE @OpId INT = (SELECT id FROM auth.users WHERE username = 'bintest_operator');
    INSERT INTO auth.user_roles (user_id, role_id) VALUES (@OpId, @OpRole);

    -- An order + allocation on U1, so picking from a held bin can be tried.
    -- Needs any existing party and ship-from address.
    DECLARE @PartyId INT = (SELECT TOP (1) party_id   FROM core.parties         ORDER BY party_id);
    DECLARE @AddrId  INT = (SELECT TOP (1) address_id FROM core.party_addresses ORDER BY address_id);
    DECLARE @HasPickFixture BIT = CASE WHEN @PartyId IS NOT NULL AND @AddrId IS NOT NULL THEN 1 ELSE 0 END;
    DECLARE @AllocId INT = NULL;

    IF @HasPickFixture = 1
    BEGIN
        INSERT INTO outbound.shipments (shipment_ref, vehicle_ref, ship_from_address_id, shipment_status)
        VALUES ('BINTEST-SHIP', 'BINTEST-VEH', @AddrId, 'OPEN');
        DECLARE @PShipId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, shipment_id, order_status_code)
        VALUES ('BINTEST-ORD', @PartyId, @PShipId, 'ALLOCATED');
        DECLARE @POrdId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_lines
            (outbound_order_id, line_no, sku_id, ordered_qty, allocated_qty, picked_qty, line_status_code)
        VALUES (@POrdId, 1, @SkuId, 10, 10, 0, 'ALLOCATED');
        DECLARE @PLineId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_allocations
            (outbound_line_id, inventory_unit_id, allocated_qty, allocation_status)
        VALUES (@PLineId, @U1, 10, 'PENDING');
        SET @AllocId = SCOPE_IDENTITY();
    END

    DECLARE @HasStage BIT = CASE WHEN EXISTS (
        SELECT 1
        FROM locations.bins b
        JOIN locations.storage_types st ON st.storage_type_id = b.storage_type_id
        WHERE st.storage_type_code = 'STAGE' AND b.is_active = 1
    ) THEN 1 ELSE 0 END;

    ----------------------------------------------------------------
    -- 1. Start: the snapshot is exactly the active bins holding stock
    ----------------------------------------------------------------
    -- A storage type that does not exist starts nothing
    EXEC warehouse.usp_count_start_bin @storage_type_code = 'BINTEST-NOPE', @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_sessions WHERE count_type_code = 'BIN_COUNT' AND status_code = 'OPEN')
        RAISERROR('FAIL: starting a bin count for a storage type that does not exist created a session.', 16, 1);

    EXEC warehouse.usp_count_start_bin @storage_type_code = 'BINTEST-A', @user_id = @OpId;

    DECLARE @CountA INT = (SELECT count_id FROM warehouse.count_sessions
                           WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StA AND status_code = 'OPEN');
    IF @CountA IS NULL
        RAISERROR('FAIL: starting a bin count did not create an OPEN BIN_COUNT session.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_lines WHERE count_id = @CountA) <> 4
        RAISERROR('FAIL: the snapshot should hold exactly the 4 active bins with stock (A1, A2, A3, A6).', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id
               WHERE l.count_id = @CountA AND b.bin_code IN ('BINTEST-A4', 'BINTEST-A5', 'BINTEST-B1'))
        RAISERROR('FAIL: an empty bin, an inactive bin or a bin of another storage type was snapshotted.', 16, 1);

    EXEC warehouse.usp_count_start_bin @storage_type_code = 'BINTEST-A', @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_sessions
        WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StA AND status_code = 'OPEN') <> 1
        RAISERROR('FAIL: starting again created a second OPEN count instead of resuming.', 16, 1);

    -- A sweep cannot run beside an open single-storage-type count ...
    EXEC warehouse.usp_count_start_bin @storage_type_code = NULL, @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_sessions WHERE count_type_code = 'BIN_COUNT' AND storage_type_id IS NULL AND status_code = 'OPEN')
        RAISERROR('FAIL: a sweep was started beside an open single-storage-type count.', 16, 1);

    -- ... but one storage type can run beside another
    EXEC warehouse.usp_count_start_bin @storage_type_code = 'BINTEST-B', @user_id = @OpId;
    EXEC warehouse.usp_count_start_bin @storage_type_code = 'BINTEST-C', @user_id = @OpId;

    DECLARE @CountB INT = (SELECT count_id FROM warehouse.count_sessions
                           WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StB AND status_code = 'OPEN');
    DECLARE @CountC INT = (SELECT count_id FROM warehouse.count_sessions
                           WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StC AND status_code = 'OPEN');
    IF @CountB IS NULL OR @CountC IS NULL
        RAISERROR('FAIL: bin counts of different storage types could not be open together.', 16, 1);

    DECLARE @LA1 INT = (SELECT l.count_line_id FROM warehouse.count_lines l WHERE l.count_id = @CountA AND l.bin_id = @A1);
    DECLARE @LA2 INT = (SELECT l.count_line_id FROM warehouse.count_lines l WHERE l.count_id = @CountA AND l.bin_id = @A2);
    DECLARE @LA3 INT = (SELECT l.count_line_id FROM warehouse.count_lines l WHERE l.count_id = @CountA AND l.bin_id = @A3);
    DECLARE @LA6 INT = (SELECT l.count_line_id FROM warehouse.count_lines l WHERE l.count_id = @CountA AND l.bin_id = @A6);
    DECLARE @LB1 INT = (SELECT l.count_line_id FROM warehouse.count_lines l WHERE l.count_id = @CountB AND l.bin_id = @B1);
    DECLARE @LC1 INT = (SELECT l.count_line_id FROM warehouse.count_lines l WHERE l.count_id = @CountC AND l.bin_id = @C1);

    PRINT 'PASS: start snapshots exactly the occupied bins; resumes; refuses a sweep beside a scoped count.';

    ----------------------------------------------------------------
    -- 2. Open: the hold, and what refuses it
    ----------------------------------------------------------------
    -- Wrong case and bins outside the count change nothing
    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'bintest-a2', @user_id = @OpId;
    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A4', @user_id = @OpId;
    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-B1', @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_lines WHERE count_id = @CountA AND line_status_code <> 'PENDING')
        RAISERROR('FAIL: a wrong-case bin, or a bin not in the count, opened a line.', 16, 1);

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE reservation_type = 'COUNT' AND bin_id IN (@A2, @A4, @B1))
        RAISERROR('FAIL: a COUNT hold was taken on a bin that could not be opened.', 16, 1);

    -- Work in progress refuses: an open task to / from the bin ...
    INSERT INTO warehouse.warehouse_tasks
        (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id, task_state_code, expires_at, created_by)
    VALUES ('PICK', @U3, @A2, @A6, 'OPN', DATEADD(MINUTE, 5, SYSUTCDATETIME()), @UserId);

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A2', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA2) <> 'PENDING'
        RAISERROR('FAIL: a bin with an open task was opened for counting.', 16, 1);

    DELETE FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U3;

    -- ... or another unexpired reservation on it
    INSERT INTO locations.bin_reservations (bin_id, reservation_type, reserved_by, expires_at)
    VALUES (@A2, 'MOVE', @UserId, DATEADD(MINUTE, 5, SYSUTCDATETIME()));

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A2', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA2) <> 'PENDING'
        RAISERROR('FAIL: a bin with another reservation on it was opened for counting.', 16, 1);

    DELETE FROM locations.bin_reservations WHERE bin_id = @A2;

    -- A1 opens: held, tied to its line, in the future
    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A1', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA1) <> 'COUNTING'
        RAISERROR('FAIL: opening a bin did not set the line COUNTING.', 16, 1);

    DECLARE @OpenedAt DATETIME2(3) = (SELECT opened_at FROM warehouse.count_lines WHERE count_line_id = @LA1);
    IF @OpenedAt IS NULL
        RAISERROR('FAIL: opened_at was not recorded.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bin_reservations
                   WHERE bin_id = @A1 AND reservation_type = 'COUNT' AND count_line_id = @LA1
                     AND expires_at > SYSUTCDATETIME())
        RAISERROR('FAIL: opening a bin did not take an unexpired COUNT hold tied to the line.', 16, 1);

    PRINT 'PASS: open takes the hold, and refuses wrong case, unknown bins and work in progress.';

    ----------------------------------------------------------------
    -- 3. The lock is honoured
    ----------------------------------------------------------------
    IF warehouse.fn_bin_receive_block_code(@A1) IS NULL
       OR warehouse.fn_bin_receive_block_code(@A1) <> N'ERRCNT12'
        RAISERROR('FAIL: a bin being counted still accepts stock (fn_bin_receive_block_code).', 16, 1);

    IF warehouse.fn_unit_move_block_code(@U1, NULL) IS NULL
       OR warehouse.fn_unit_move_block_code(@U1, NULL) <> N'ERRCNT12'
        RAISERROR('FAIL: a unit in a bin being counted is still free to be moved (fn_unit_move_block_code).', 16, 1);

    -- Controls: a bin that is NOT held is unaffected
    IF warehouse.fn_bin_receive_block_code(@A6) IS NOT NULL
        RAISERROR('FAIL (control): an ordinary bin refused stock.', 16, 1);

    IF warehouse.fn_unit_move_block_code(@U6, NULL) IS NOT NULL
        RAISERROR('FAIL (control): a unit in an ordinary bin was not free to move.', 16, 1);

    -- A move out of the held bin, and into it, creates no task
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'BINTEST-U1', @destination_bin_code = 'BINTEST-A6', @user_id = @UserId;
    IF EXISTS (SELECT 1 FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U1 AND task_type_code = 'MOVE')
        RAISERROR('FAIL: a unit was moved out of a bin being counted.', 16, 1);

    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'BINTEST-U6', @destination_bin_code = 'BINTEST-A1', @user_id = @UserId;
    IF EXISTS (SELECT 1 FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U6 AND task_type_code = 'MOVE')
        RAISERROR('FAIL: a unit was moved into a bin being counted.', 16, 1);

    -- Putaway never suggests a bin being counted (C1 is the only bin of its type)
    EXEC warehouse.usp_count_open_bin @count_id = @CountC, @bin_code = 'BINTEST-C1', @user_id = @OpId;

    DECLARE @Suggested INT = NULL;
    EXEC locations.usp_suggest_putaway_bin @inventory_unit_id = @UNew, @suggested_bin_id = @Suggested OUTPUT;
    IF @Suggested IS NOT NULL
        RAISERROR('FAIL: putaway suggested a bin that is being counted.', 16, 1);

    -- Picking from a held bin is refused: the allocation is not turned into a task
    IF @HasPickFixture = 1
    BEGIN
        EXEC outbound.usp_pick_create
            @allocation_id = @AllocId, @destination_bin_code = NULL, @user_id = @UserId, @session_id = NULL;

        IF (SELECT allocation_status FROM outbound.outbound_allocations WHERE allocation_id = @AllocId) <> 'PENDING'
           OR EXISTS (SELECT 1 FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U1 AND task_type_code = 'PICK')
            RAISERROR('FAIL: a pick task was created for a pallet in a bin being counted.', 16, 1);
    END
    ELSE
        PRINT 'SKIPPED: pick-from-held-bin check (no party / address in the database to hang an order on).';

    -- An EXPIRED hold locks nothing (the lock expires so an abandoned count cannot pin a bin)
    UPDATE locations.bin_reservations
    SET expires_at = DATEADD(MINUTE, -1, SYSUTCDATETIME())
    WHERE bin_id = @A1 AND reservation_type = 'COUNT';

    IF locations.fn_bin_is_being_counted(@A1) <> 0
        RAISERROR('FAIL: an expired COUNT hold still locks the bin.', 16, 1);

    IF warehouse.fn_bin_receive_block_code(@A1) IS NOT NULL
        RAISERROR('FAIL: an expired COUNT hold still refuses stock into the bin.', 16, 1);

    PRINT 'PASS: a held bin takes nothing in, lets nothing out, is not suggested, and cannot be picked from; an expired hold locks nothing.';

    ----------------------------------------------------------------
    -- 4. Scan - blind, and what refuses
    ----------------------------------------------------------------
    -- (A1's hold has just been expired above: first the refused scan, then
    --  re-open, which resumes the line and renews the hold.)
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U1', @counted_qty = 11, @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_scans WHERE count_line_id = @LA1)
        RAISERROR('FAIL: a scan was recorded after the bin''s hold had expired.', 16, 1);

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A1', @user_id = @OpId;

    IF (SELECT opened_at FROM warehouse.count_lines WHERE count_line_id = @LA1) <> @OpenedAt
        RAISERROR('FAIL: resuming a bin changed its original opened_at (the ledger check would miss the gap).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM locations.bin_reservations
                   WHERE bin_id = @A1 AND reservation_type = 'COUNT' AND count_line_id = @LA1
                     AND expires_at > SYSUTCDATETIME())
        RAISERROR('FAIL: re-opening a bin did not renew its hold.', 16, 1);

    IF (SELECT COUNT(*) FROM locations.bin_reservations WHERE bin_id = @A1 AND reservation_type = 'COUNT') <> 1
        RAISERROR('FAIL: re-opening a bin left more than one COUNT hold on it.', 16, 1);

    -- A scan before the bin is opened
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A6', @scanned_ref = 'BINTEST-U6', @counted_qty = 60, @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_scans WHERE count_line_id = @LA6)
        RAISERROR('FAIL: a scan was recorded for a bin that had not been opened.', 16, 1);

    -- Quantity 0, and a blank SSCC
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U1', @counted_qty = 0, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = '   ', @counted_qty = 5, @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_scans WHERE count_line_id = @LA1)
        RAISERROR('FAIL: a zero quantity or a blank SSCC was recorded.', 16, 1);

    -- A pallet that matches
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U1', @counted_qty = 10, @user_id = @OpId;

    -- A quantity that differs from the system's, for a pallet recorded HERE:
    -- not recorded until the operator confirms it
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U2', @counted_qty = 25, @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_scans WHERE count_line_id = @LA1 AND scanned_ref = 'BINTEST-U2')
        RAISERROR('FAIL: a quantity that differs from the system record was recorded without confirmation.', 16, 1);

    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U2', @counted_qty = 25,
        @confirm_difference = 1, @user_id = @OpId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_scans
                   WHERE count_line_id = @LA1 AND scanned_ref = 'BINTEST-U2'
                     AND counted_qty = 25 AND quantity_confirmed = 1 AND scanned_by = @OpId)
        RAISERROR('FAIL: the confirmed quantity was not recorded as confirmed, by the operator.', 16, 1);

    -- Scanning again replaces: never a second row
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U1', @counted_qty = 10, @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_scans WHERE count_line_id = @LA1 AND scanned_ref = 'BINTEST-U1') <> 1
        RAISERROR('FAIL: scanning a pallet again created a second row instead of replacing.', 16, 1);

    -- Pallets that are not recorded in this bin are simply recorded: no prompt,
    -- even where the quantity differs (U6: counted 55, system 60)
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-NOPE', @counted_qty = 5, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U6', @counted_qty = 55, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-USHP', @counted_qty = 10, @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_scans WHERE count_line_id = @LA1) <> 5
        RAISERROR('FAIL: expected 5 scans (U1, U2, an unknown SSCC, U6 and a shipped pallet).', 16, 1);

    -- U9 is deliberately NOT scanned
    PRINT 'PASS: scanning is blind, confirms a differing quantity, replaces on re-scan, and refuses bad input.';

    ----------------------------------------------------------------
    -- 5. Finish: every difference a finding, no record changed
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'BINTEST-A1', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA1) <> 'DIFFERENCES'
        RAISERROR('FAIL: a bin with differences did not finish as DIFFERENCES.', 16, 1);

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE count_line_id = @LA1)
        RAISERROR('FAIL: finishing a bin did not release its hold.', 16, 1);

    IF warehouse.fn_bin_receive_block_code(@A1) IS NOT NULL
        RAISERROR('FAIL: the bin still refuses stock after being finished.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_findings WHERE count_line_id = @LA1) <> 5
        RAISERROR('FAIL: expected exactly 5 findings (QTY_DIFFERENCE, MISSING, UNKNOWN_UNIT, MISPLACED, NOT_CORRECTED).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @LA1 AND inventory_unit_id = @U2 AND finding_code = 'QTY_DIFFERENCE'
                     AND counted_qty = 25 AND system_qty = 20 AND found_by = @OpId)
        RAISERROR('FAIL: the quantity difference was not recorded with counted 25 / system 20.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @LA1 AND inventory_unit_id = @U9 AND finding_code = 'MISSING'
                     AND scanned_ref = 'BINTEST-U9' AND counted_qty IS NULL AND system_qty = 90)
        RAISERROR('FAIL: the pallet the system holds but nobody scanned was not recorded MISSING (system 90).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @LA1 AND inventory_unit_id = @U6 AND finding_code = 'MISPLACED'
                     AND previous_bin_id = @A6 AND counted_qty = 55 AND system_qty = 60)
        RAISERROR('FAIL: a pallet scanned here but recorded in A6 was not recorded MISPLACED (previous bin A6).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @LA1 AND scanned_ref = 'BINTEST-NOPE'
                     AND finding_code = 'UNKNOWN_UNIT' AND inventory_unit_id IS NULL AND counted_qty = 5)
        RAISERROR('FAIL: an unknown SSCC was not recorded UNKNOWN_UNIT.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @LA1 AND scanned_ref = 'BINTEST-USHP'
                     AND finding_code = 'NOT_CORRECTED' AND reason_code = 'ERRCNT06')
        RAISERROR('FAIL: a shipped pallet was not recorded NOT_CORRECTED / ERRCNT06.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_findings WHERE count_line_id = @LA1 AND inventory_unit_id = @U1)
        RAISERROR('FAIL: the pallet that matched produced a finding.', 16, 1);

    -- THE rule: a count changes no stock record
    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @U6) <> @A6
        RAISERROR('FAIL: a count relocated a pallet (it must only record).', 16, 1);

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @U9) <> @A1
       OR (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @U9) <> 'PTW'
        RAISERROR('FAIL: a count removed or changed a pallet it reported MISSING.', 16, 1);

    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @U2) <> 20
        RAISERROR('FAIL: a count changed a quantity (it must only record).', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_movements m
               JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id
               WHERE u.external_ref LIKE 'BINTEST-%')
        RAISERROR('FAIL: a count wrote to the movement ledger (it must only record).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.v_count_findings
                   WHERE count_id = @CountA AND finding_code = 'QTY_DIFFERENCE'
                     AND counted_qty = 25 AND system_qty = 20 AND resolution_code IS NULL)
        RAISERROR('FAIL: the findings view does not show counted vs system quantity and an undecided resolution.', 16, 1);

    -- The same bin cannot be finished twice
    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'BINTEST-A1', @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_findings WHERE count_line_id = @LA1) <> 5
        RAISERROR('FAIL: finishing a bin twice added findings.', 16, 1);

    PRINT 'PASS: finish records every difference as a finding and changes no stock record.';

    ----------------------------------------------------------------
    -- 5b. The lock is released: the same things now work
    ----------------------------------------------------------------
    EXEC warehouse.usp_bin_to_bin_move_create
        @external_ref = 'BINTEST-U1', @destination_bin_code = 'BINTEST-A6', @user_id = @UserId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U1 AND task_type_code = 'MOVE')
        RAISERROR('FAIL: a unit could not be moved out of a bin once its count had finished.', 16, 1);

    -- put things back for the rest of the test
    DELETE FROM locations.bin_reservations WHERE bin_id = @A6 AND reservation_type = 'MOVE';
    DELETE FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U1;

    IF @HasPickFixture = 1 AND @HasStage = 1
    BEGIN
        EXEC outbound.usp_pick_create
            @allocation_id = @AllocId, @destination_bin_code = NULL, @user_id = @UserId, @session_id = NULL;

        IF (SELECT allocation_status FROM outbound.outbound_allocations WHERE allocation_id = @AllocId) <> 'CONFIRMED'
            RAISERROR('FAIL: a pick could not be created for a pallet once its bin''s count had finished.', 16, 1);

        DELETE FROM warehouse.warehouse_tasks WHERE inventory_unit_id = @U1;
    END
    ELSE
        PRINT 'SKIPPED: pick-after-release check (needs an order fixture and a STAGE bin).';

    -- C1: finish it, and putaway may suggest it again
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountC, @bin_code = 'BINTEST-C1', @scanned_ref = 'BINTEST-U7', @counted_qty = 70, @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @CountC, @bin_code = 'BINTEST-C1', @user_id = @OpId;

    SET @Suggested = NULL;
    EXEC locations.usp_suggest_putaway_bin @inventory_unit_id = @UNew, @suggested_bin_id = @Suggested OUTPUT;
    IF @Suggested IS NULL OR @Suggested <> @C1
        RAISERROR('FAIL: putaway does not suggest a bin again once its count has finished.', 16, 1);

    PRINT 'PASS: once finished, moves, picks and putaway work on the bin again.';

    ----------------------------------------------------------------
    -- 6. A clean bin is MATCHED, with no findings
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A2', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A2', @scanned_ref = 'BINTEST-U3', @counted_qty = 30, @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'BINTEST-A2', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA2) <> 'MATCHED'
        RAISERROR('FAIL: a bin where everything agreed did not finish as MATCHED.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_findings WHERE count_line_id = @LA2)
        RAISERROR('FAIL: a bin where everything agreed has findings.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_scans WHERE count_line_id = @LA2) <> 1
        RAISERROR('FAIL: the scans of a matched bin were not kept as evidence.', 16, 1);

    PRINT 'PASS: a bin where everything agrees is MATCHED, and its scans are kept.';

    ----------------------------------------------------------------
    -- 7. The safeguard: the ledger shows the bin changed
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A3', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A3', @scanned_ref = 'BINTEST-U4', @counted_qty = 40, @user_id = @OpId;

    -- Something touches the bin in the ledger after it was opened - as a writer
    -- that ignores the hold would (the row is dated just after the bin opened)
    DECLARE @A3OpenedAt DATETIME2(3) = (SELECT opened_at FROM warehouse.count_lines WHERE count_line_id = @LA3);

    INSERT INTO inventory.inventory_movements
        (inventory_unit_id, sku_id, moved_qty, from_bin_id, to_bin_id,
         from_state_code, to_state_code, from_status_code, to_status_code,
         movement_type, reference_type, reference_id, moved_at, moved_by_user_id)
    VALUES
        (@U4, @SkuId, 40, @A3, @A6, 'PTW', 'PTW', 'AV', 'AV',
         'BIN_MOVE', 'TEST', NULL, DATEADD(MILLISECOND, 1, @A3OpenedAt), @UserId);

    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'BINTEST-A3', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA3) <> 'PENDING'
        RAISERROR('FAIL: a bin that changed while being counted was accepted instead of sent back to PENDING.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_scans WHERE count_line_id = @LA3)
        RAISERROR('FAIL: the scans of a bin that changed under the count were kept.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_findings WHERE count_line_id = @LA3)
        RAISERROR('FAIL: findings were recorded for a bin that changed under the count.', 16, 1);

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE count_line_id = @LA3)
        RAISERROR('FAIL: the hold was not released when the bin was sent back for recounting.', 16, 1);

    IF (SELECT opened_at FROM warehouse.count_lines WHERE count_line_id = @LA3) IS NOT NULL
        RAISERROR('FAIL: opened_at was not cleared, so the old movement would still count against the recount.', 16, 1);

    -- Counted again, it is accepted: the old movement predates the new open
    WAITFOR DELAY '00:00:00.100';

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A3', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A3', @scanned_ref = 'BINTEST-U4', @counted_qty = 40, @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'BINTEST-A3', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA3) <> 'MATCHED'
        RAISERROR('FAIL: a bin recounted after a change was not accepted.', 16, 1);

    PRINT 'PASS: a bin the ledger shows changed is sent back, and accepted when counted again.';

    ----------------------------------------------------------------
    -- 8. Cancel
    ----------------------------------------------------------------
    WAITFOR DELAY '00:00:00.100';

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A6', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A6', @scanned_ref = 'BINTEST-U6', @counted_qty = 60, @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_scans WHERE count_line_id = @LA6) <> 1
        RAISERROR('FAIL (setup): the scan before cancel was not recorded.', 16, 1);

    EXEC warehouse.usp_count_cancel_bin @count_id = @CountA, @bin_code = 'BINTEST-A6', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA6) <> 'PENDING'
       OR EXISTS (SELECT 1 FROM warehouse.count_scans WHERE count_line_id = @LA6)
       OR EXISTS (SELECT 1 FROM locations.bin_reservations WHERE count_line_id = @LA6)
       OR (SELECT opened_at FROM warehouse.count_lines WHERE count_line_id = @LA6) IS NOT NULL
        RAISERROR('FAIL: cancelling a bin did not discard the scans, release the hold and return it to PENDING.', 16, 1);

    -- And it can be counted afterwards
    WAITFOR DELAY '00:00:00.100';

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'BINTEST-A6', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit
        @count_id = @CountA, @bin_code = 'BINTEST-A6', @scanned_ref = 'BINTEST-U6', @counted_qty = 60, @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'BINTEST-A6', @user_id = @OpId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @LA6) <> 'MATCHED'
        RAISERROR('FAIL: a bin counted after a cancel did not finish MATCHED.', 16, 1);

    PRINT 'PASS: cancel discards the scans and releases the hold; the bin can be counted afterwards.';

    ----------------------------------------------------------------
    -- 9. Close
    ----------------------------------------------------------------
    -- A bin still open blocks closing (B1 opened, count B)
    EXEC warehouse.usp_count_open_bin @count_id = @CountB, @bin_code = 'BINTEST-B1', @user_id = @OpId;
    EXEC warehouse.usp_count_close @count_id = @CountB, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountB) <> 'OPEN'
        RAISERROR('FAIL: a count with a bin still open was closed.', 16, 1);

    -- Cancel it, then close with the bin uncounted and nothing to review: CLOSED
    EXEC warehouse.usp_count_cancel_bin @count_id = @CountB, @bin_code = 'BINTEST-B1', @user_id = @OpId;
    EXEC warehouse.usp_count_close @count_id = @CountB, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountB) <> 'CLOSED'
        RAISERROR('FAIL: a count closed with bins uncounted and nothing to review should be CLOSED.', 16, 1);

    -- C: every bin counted, nothing to review: COMPLETE
    EXEC warehouse.usp_count_close @count_id = @CountC, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountC) <> 'COMPLETE'
        RAISERROR('FAIL: a count with every bin counted and nothing to review should be COMPLETE.', 16, 1);

    -- A: unresolved findings: REVIEW
    EXEC warehouse.usp_count_close @count_id = @CountA, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountA) <> 'REVIEW'
        RAISERROR('FAIL: a count with unresolved findings should close as REVIEW.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.v_count_sessions
                   WHERE count_id = @CountA AND findings_to_review = 5
                     AND matched_bins = 3 AND difference_bins = 1 AND counting_bins = 0 AND pending_bins = 0)
        RAISERROR('FAIL: the count view does not show 3 matched / 1 difference bin / 5 findings to review.', 16, 1);

    PRINT 'PASS: close is refused while a bin is open, and ends REVIEW / CLOSED / COMPLETE as it should.';

    ----------------------------------------------------------------
    -- 10. Guards: each family refuses the other's count
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_start_empty_bin @storage_type_code = 'BINTEST-A', @user_id = @OpId;

    DECLARE @EmptyCount INT = (SELECT count_id FROM warehouse.count_sessions
                               WHERE count_type_code = 'EMPTY_BIN' AND storage_type_id = @StA AND status_code = 'OPEN');
    IF @EmptyCount IS NULL
        RAISERROR('FAIL (setup): an empty-bin count of BINTEST-A could not be started.', 16, 1);

    EXEC warehouse.usp_count_open_bin @count_id = @EmptyCount, @bin_code = 'BINTEST-A4', @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE reservation_type = 'COUNT' AND bin_id = @A4)
       OR EXISTS (SELECT 1 FROM warehouse.count_lines WHERE count_id = @EmptyCount AND line_status_code <> 'PENDING')
        RAISERROR('FAIL: a bin-count procedure accepted an empty-bin count.', 16, 1);

    EXEC warehouse.usp_count_close @count_id = @EmptyCount, @user_id = @OpId;

    -- The sweep (no storage type): starts, resumes, and refuses what overlaps it
    EXEC warehouse.usp_count_start_bin @storage_type_code = NULL, @user_id = @OpId;

    DECLARE @Sweep INT = (SELECT count_id FROM warehouse.count_sessions
                          WHERE count_type_code = 'BIN_COUNT' AND storage_type_id IS NULL AND status_code = 'OPEN');
    IF @Sweep IS NULL
        RAISERROR('FAIL: a sweep (no storage type) could not be started.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id
        WHERE l.count_id = @Sweep
          AND b.bin_code IN ('BINTEST-A1', 'BINTEST-A2', 'BINTEST-A3', 'BINTEST-A6', 'BINTEST-B1', 'BINTEST-C1')) <> 6
        RAISERROR('FAIL: the sweep did not snapshot the occupied bins of every storage type.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id
               WHERE l.count_id = @Sweep AND b.bin_code IN ('BINTEST-A4', 'BINTEST-A5'))
        RAISERROR('FAIL: the sweep snapshotted an empty or an inactive bin.', 16, 1);

    EXEC warehouse.usp_count_start_bin @storage_type_code = NULL, @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_sessions
        WHERE count_type_code = 'BIN_COUNT' AND storage_type_id IS NULL AND status_code = 'OPEN') <> 1
        RAISERROR('FAIL: starting a sweep again created a second sweep instead of resuming.', 16, 1);

    EXEC warehouse.usp_count_start_bin @storage_type_code = 'BINTEST-A', @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_sessions
               WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StA AND status_code = 'OPEN')
        RAISERROR('FAIL: a single-storage-type count was started beside an open sweep.', 16, 1);

    -- The empty-bin procedures refuse a bin count
    EXEC warehouse.usp_count_confirm_empty @count_id = @Sweep, @bin_code = 'BINTEST-A1', @user_id = @OpId;
    EXEC warehouse.usp_count_report_stock  @count_id = @Sweep, @bin_code = 'BINTEST-A1', @scanned_ref = 'BINTEST-U6', @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_lines WHERE count_id = @Sweep AND line_status_code <> 'PENDING')
       OR EXISTS (SELECT 1 FROM warehouse.count_findings f JOIN warehouse.count_lines l ON l.count_line_id = f.count_line_id
                  WHERE l.count_id = @Sweep)
        RAISERROR('FAIL: an empty-bin procedure accepted a bin count.', 16, 1);

    EXEC warehouse.usp_count_close @count_id = @Sweep, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @Sweep) <> 'CLOSED'
        RAISERROR('FAIL: closing an untouched sweep should give CLOSED.', 16, 1);

    PRINT 'PASS: a sweep covers every storage type, resumes, refuses overlaps; the two count families refuse each other.';

    ----------------------------------------------------------------
    -- 11. Ad hoc: a hand-picked list of bins
    ----------------------------------------------------------------
    DECLARE @sep  NCHAR(1) = NCHAR(30);
    DECLARE @list NVARCHAR(MAX);

    -- An empty list, an inactive bin, a bin that does not exist and a wrong-case
    -- bin each start NOTHING
    SET @list = N'';
    EXEC warehouse.usp_count_start_adhoc @bin_codes = @list, @user_id = @OpId;

    SET @list = N'BINTEST-A1' + @sep + N'BINTEST-A5';          -- A5 is inactive
    EXEC warehouse.usp_count_start_adhoc @bin_codes = @list, @user_id = @OpId;

    SET @list = N'BINTEST-A1' + @sep + N'BINTEST-NOPE';        -- no such bin
    EXEC warehouse.usp_count_start_adhoc @bin_codes = @list, @user_id = @OpId;

    SET @list = N'BINTEST-A1' + @sep + N'bintest-a2';          -- wrong case
    EXEC warehouse.usp_count_start_adhoc @bin_codes = @list, @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM warehouse.count_sessions WHERE scope_code = 'ADHOC')
        RAISERROR('FAIL: an ad hoc count with an empty or invalid list was started.', 16, 1);

    -- A good list: an occupied bin and an EMPTY bin; A1 named twice is one line
    SET @list = N'BINTEST-A1' + @sep + N'BINTEST-A4' + @sep + N'BINTEST-A1';
    EXEC warehouse.usp_count_start_adhoc @bin_codes = @list, @user_id = @OpId;

    DECLARE @AdhocX INT = (SELECT TOP (1) count_id FROM warehouse.count_sessions
                           WHERE scope_code = 'ADHOC' AND status_code = 'OPEN' ORDER BY count_id);
    IF @AdhocX IS NULL
        RAISERROR('FAIL: an ad hoc count could not be started.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_sessions
                   WHERE count_id = @AdhocX AND count_type_code = 'BIN_COUNT'
                     AND storage_type_id IS NULL AND scope_code = 'ADHOC')
        RAISERROR('FAIL: an ad hoc count is not a BIN_COUNT with scope ADHOC and no storage type.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_lines WHERE count_id = @AdhocX) <> 2
        RAISERROR('FAIL: the ad hoc list (A1, A4, A1) should give exactly two lines.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.v_count_sessions WHERE count_id = @AdhocX AND scope_code = 'ADHOC' AND storage_type_code IS NULL)
        RAISERROR('FAIL: the count view does not show an ad hoc count as ADHOC with no storage type.', 16, 1);

    -- A sweep can run beside an open ad hoc count (it is neither a sweep nor a storage type) ...
    EXEC warehouse.usp_count_start_bin @storage_type_code = NULL, @user_id = @OpId;

    DECLARE @Sweep2 INT = (SELECT count_id FROM warehouse.count_sessions
                           WHERE scope_code = 'ALL' AND status_code = 'OPEN');
    IF @Sweep2 IS NULL
        RAISERROR('FAIL: a sweep could not be started beside an open ad hoc count.', 16, 1);

    EXEC warehouse.usp_count_close @count_id = @Sweep2, @user_id = @OpId;

    -- ... and so can a second ad hoc count, even over a bin the first one names
    SET @list = N'BINTEST-A4' + @sep + N'BINTEST-A2';
    EXEC warehouse.usp_count_start_adhoc @bin_codes = @list, @user_id = @OpId;

    DECLARE @AdhocY INT = (SELECT TOP (1) count_id FROM warehouse.count_sessions
                           WHERE scope_code = 'ADHOC' AND status_code = 'OPEN' AND count_id <> @AdhocX
                           ORDER BY count_id);
    IF @AdhocY IS NULL
        RAISERROR('FAIL: a second ad hoc count could not be open beside the first.', 16, 1);

    -- A bin that is not in an ad hoc count's list cannot be opened in it
    EXEC warehouse.usp_count_open_bin @count_id = @AdhocY, @bin_code = 'BINTEST-A1', @user_id = @OpId;

    IF EXISTS (SELECT 1 FROM locations.bin_reservations WHERE bin_id = @A1 AND reservation_type = 'COUNT')
        RAISERROR('FAIL: a bin outside an ad hoc count''s list was opened in it.', 16, 1);

    -- An EMPTY bin counted with nothing scanned: confirmed empty, MATCHED, no findings
    EXEC warehouse.usp_count_open_bin   @count_id = @AdhocX, @bin_code = 'BINTEST-A4', @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @AdhocX, @bin_code = 'BINTEST-A4', @user_id = @OpId;

    IF (SELECT l.line_status_code FROM warehouse.count_lines l WHERE l.count_id = @AdhocX AND l.bin_id = @A4) <> 'MATCHED'
       OR EXISTS (SELECT 1 FROM warehouse.count_findings f JOIN warehouse.count_lines l ON l.count_line_id = f.count_line_id
                  WHERE l.count_id = @AdhocX)
        RAISERROR('FAIL: an empty bin counted with nothing scanned was not MATCHED with no findings.', 16, 1);

    -- The same empty bin, in the other ad hoc count, with a pallet found in it
    EXEC warehouse.usp_count_open_bin   @count_id = @AdhocY, @bin_code = 'BINTEST-A4', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit  @count_id = @AdhocY, @bin_code = 'BINTEST-A4', @scanned_ref = 'BINTEST-U6', @counted_qty = 60, @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @AdhocY, @bin_code = 'BINTEST-A4', @user_id = @OpId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings f
                   JOIN warehouse.count_lines l ON l.count_line_id = f.count_line_id
                   WHERE l.count_id = @AdhocY AND f.inventory_unit_id = @U6
                     AND f.finding_code = 'MISPLACED' AND f.previous_bin_id = @A6)
        RAISERROR('FAIL: a pallet found in an "empty" bin was not recorded as MISPLACED (previous bin A6).', 16, 1);

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @U6) <> @A6
        RAISERROR('FAIL: an ad hoc count relocated a pallet (it must only record).', 16, 1);

    -- Close them: X leaves a bin uncounted with nothing to review (CLOSED);
    -- Y has an undecided finding (REVIEW)
    EXEC warehouse.usp_count_close @count_id = @AdhocX, @user_id = @OpId;
    EXEC warehouse.usp_count_close @count_id = @AdhocY, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @AdhocX) <> 'CLOSED'
       OR (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @AdhocY) <> 'REVIEW'
        RAISERROR('FAIL: the ad hoc counts should close as CLOSED (bin left, nothing to review) and REVIEW (a finding).', 16, 1);

    PRINT 'PASS: ad hoc counts take a hand-picked list (empty bins included), run beside sweeps and each other, and record like any bin count.';

    PRINT 'TEST PASSED: bin count.';

END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH

-- Cleanup (always runs)
DELETE f FROM warehouse.count_findings f
    JOIN warehouse.count_lines l    ON l.count_line_id = f.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE sc FROM warehouse.count_scans sc
    JOIN warehouse.count_lines l    ON l.count_line_id = sc.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE l FROM warehouse.count_lines l
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE s FROM warehouse.count_sessions s
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'BINTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'bintest[_]%');
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'BINTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'BINTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'BINTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'BINTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'BINTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'BINTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'BINTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'BINTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'BINTEST-%';
DELETE ur FROM auth.user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.username LIKE 'bintest[_]%';
DELETE FROM auth.users                WHERE username LIKE 'bintest[_]%';

IF @err IS NOT NULL
    RAISERROR(@err, 16, 1);
GO
