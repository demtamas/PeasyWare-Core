-- ==========================================================
-- TEST: Bin count adjustment - what a person with counts.adjust can do
--       about what a bin count found
--
--   Permission: counts.adjust is enforced (an operator is refused; manager
--             and admin are allowed); nothing changes for a refused call
--   State:    only a bin count that is in REVIEW can be decided (an OPEN one
--             is refused); each finding is decided once; an unknown finding
--             and a bad action are refused
--   Apply:    QTY_DIFFERENCE sets the quantity, and the ledger row records
--             qty_before / qty_after (moved_qty is the size of the change);
--             MISSING scraps the pallet through the shared scrap primitive
--             (placement gone, state SCR, ledger row from the counted bin);
--             MISPLACED relocates the record to the counted bin through the
--             shared relocation (ledger row old bin -> new bin, quantity left
--             alone); every apply links its ledger row to the finding
--   Re-check: applying refuses, changing nothing and leaving the finding
--             undecided, when the world has moved on since the count -
--             the record changed (ERRCNT26), the stock status does not allow
--             adjusting (ERRCNT27), the pallet is allocated to an order
--             (ERRCNT28), the pallet is mid-flow (ERRCNT29), or it has an
--             open task (ERRMOVE10, from the shared move rules)
--   Nothing to apply: an unknown pallet and a shipped one cannot be applied
--             (ERRCNT23); they can be declined, which acknowledges them
--   Decline:  needs a note; leaves the stock record alone; records who and why
--   Review:   refused (ERRCNT30) while any quantity / missing / misplaced
--             finding is undecided; unknown / shipped findings do NOT block it;
--             once decided it ends the count (CLOSED here: a bin was left
--             uncounted); nothing can be decided after the review
--   Regression: usp_write_off_unit still does what it did, now through
--             inventory.usp_apply_scrap; the primitive refuses a unit the
--             state machine does not let be scrapped
--
-- No outer transaction: the procedures roll back internally on their
-- refusal paths, so (as in 146 / 150 / 160 / 180) fixtures are cleaned
-- explicitly in a final block that always runs.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous aborted run.
DELETE f FROM warehouse.count_findings f
    JOIN warehouse.count_lines l    ON l.count_line_id = f.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE sc FROM warehouse.count_scans sc
    JOIN warehouse.count_lines l    ON l.count_line_id = sc.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE l FROM warehouse.count_lines l
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE s FROM warehouse.count_sessions s
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'ADJTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'ADJTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'ADJTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'ADJTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'ADJTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'ADJTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'ADJTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'ADJTEST-%';
DELETE ur FROM auth.user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.username LIKE 'adjtest[_]%';
DELETE FROM auth.users                WHERE username LIKE 'adjtest[_]%';
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
        ('ADJTEST-A', 'Adjust Test A'),
        ('ADJTEST-B', 'Adjust Test B');

    DECLARE @StA INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'ADJTEST-A');
    DECLARE @StB INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'ADJTEST-B');

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked) VALUES
        ('ADJTEST-A1', @StA, 20, 1, 0),   -- the counted bin
        ('ADJTEST-A6', @StA, 20, 1, 0),   -- where "misplaced" pallets are recorded; left uncounted
        ('ADJTEST-B1', @StB, 4,  1, 0);

    DECLARE @A1 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'ADJTEST-A1');
    DECLARE @A6 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'ADJTEST-A6');
    DECLARE @B1 INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'ADJTEST-B1');

    INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, preferred_storage_type_id)
    VALUES ('ADJTEST-SKU', 'Adjust Test SKU', '09999900001911', 'EA', @StA);
    DECLARE @SkuId INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'ADJTEST-SKU');

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code) VALUES
        (@SkuId, 'ADJTEST-U1',    10, 'PTW', 'AV'),   -- agrees with the count
        (@SkuId, 'ADJTEST-U2',    20, 'PTW', 'AV'),   -- counted 25  -> QTY_DIFFERENCE, applies
        (@SkuId, 'ADJTEST-U9',    90, 'PTW', 'AV'),   -- not scanned -> MISSING, applies (scrap)
        (@SkuId, 'ADJTEST-UPK',    5, 'PKD', 'AV'),   -- not scanned, but mid-flow   -> ERRCNT29
        (@SkuId, 'ADJTEST-UMV',   55, 'PTW', 'AV'),   -- not scanned, moves away     -> ERRCNT26
        (@SkuId, 'ADJTEST-UCH',   60, 'PTW', 'AV'),   -- counted 65, quantity drifts -> ERRCNT26
        (@SkuId, 'ADJTEST-UQ',    40, 'PTW', 'AV'),   -- counted 45, then allocated  -> ERRCNT28
        (@SkuId, 'ADJTEST-UBL',   15, 'PTW', 'BL'),   -- counted 18, blocked stock   -> ERRCNT27
        (@SkuId, 'ADJTEST-U6',    60, 'PTW', 'AV'),   -- recorded in A6, scanned in A1 -> MISPLACED, applies
        (@SkuId, 'ADJTEST-UM2',    7, 'PTW', 'AV'),   -- recorded in A6, scanned in A1, then an open task -> ERRMOVE10
        (@SkuId, 'ADJTEST-USHP',  10, 'SHP', 'AV'),   -- shipped, scanned in A1      -> NOT_CORRECTED
        (@SkuId, 'ADJTEST-UB',    30, 'PTW', 'AV'),   -- the second count (B1)
        (@SkuId, 'ADJTEST-UEXP',   5, 'PTW', 'EX');   -- for the write-off regression

    DECLARE @U1   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-U1');
    DECLARE @U2   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-U2');
    DECLARE @U9   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-U9');
    DECLARE @UPk  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UPK');
    DECLARE @UMv  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UMV');
    DECLARE @UCh  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UCH');
    DECLARE @UQ   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UQ');
    DECLARE @UBl  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UBL');
    DECLARE @U6   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-U6');
    DECLARE @UM2  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UM2');
    DECLARE @UB   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UB');
    DECLARE @UExp INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'ADJTEST-UEXP');

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    SELECT u.inventory_unit_id,
           CASE u.external_ref
                WHEN 'ADJTEST-U6'   THEN @A6
                WHEN 'ADJTEST-UM2'  THEN @A6
                WHEN 'ADJTEST-UEXP' THEN @A6
                WHEN 'ADJTEST-UB'   THEN @B1
                ELSE @A1
           END
    FROM inventory.inventory_units u
    WHERE u.external_ref LIKE 'ADJTEST-%'
      AND u.external_ref <> 'ADJTEST-USHP';       -- shipped: no placement

    -- The counter is an OPERATOR; the people who decide are a manager and an admin
    DECLARE @OpRole  INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    DECLARE @MgrRole INT = (SELECT id FROM auth.roles WHERE role_name = 'manager');
    DECLARE @AdmRole INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');

    IF @OpRole IS NULL OR @MgrRole IS NULL OR @AdmRole IS NULL
        RAISERROR('TEST SETUP FAILED: operator / manager / admin role not found.', 16, 1);

    INSERT INTO auth.users (username, display_name, email, salt, is_active) VALUES
        ('adjtest_operator', 'Adjust Test Operator (temp)', 'adjtest_operator@pw.local', 0x00, 1),
        ('adjtest_manager',  'Adjust Test Manager (temp)',  'adjtest_manager@pw.local',  0x00, 1),
        ('adjtest_admin',    'Adjust Test Admin (temp)',    'adjtest_admin@pw.local',    0x00, 1);

    DECLARE @OpId  INT = (SELECT id FROM auth.users WHERE username = 'adjtest_operator');
    DECLARE @MgrId INT = (SELECT id FROM auth.users WHERE username = 'adjtest_manager');
    DECLARE @AdmId INT = (SELECT id FROM auth.users WHERE username = 'adjtest_admin');

    INSERT INTO auth.user_roles (user_id, role_id) VALUES
        (@OpId,  @OpRole),
        (@MgrId, @MgrRole),
        (@AdmId, @AdmRole);

    DECLARE @rc NVARCHAR(20);

    ----------------------------------------------------------------
    -- Setup: the operator counts A1 (blind), and B1
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_start_bin @storage_type_code = 'ADJTEST-A', @user_id = @OpId;
    EXEC warehouse.usp_count_start_bin @storage_type_code = 'ADJTEST-B', @user_id = @OpId;

    DECLARE @CountA INT = (SELECT count_id FROM warehouse.count_sessions
                           WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StA AND status_code = 'OPEN');
    DECLARE @CountB INT = (SELECT count_id FROM warehouse.count_sessions
                           WHERE count_type_code = 'BIN_COUNT' AND storage_type_id = @StB AND status_code = 'OPEN');
    IF @CountA IS NULL OR @CountB IS NULL
        RAISERROR('TEST SETUP FAILED: the two bin counts did not start.', 16, 1);

    DECLARE @LA1 INT = (SELECT count_line_id FROM warehouse.count_lines WHERE count_id = @CountA AND bin_id = @A1);

    EXEC warehouse.usp_count_open_bin @count_id = @CountA, @bin_code = 'ADJTEST-A1', @user_id = @OpId;

    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-U1',   @counted_qty = 10, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-U2',   @counted_qty = 25, @confirm_difference = 1, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-UQ',   @counted_qty = 45, @confirm_difference = 1, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-UBL',  @counted_qty = 18, @confirm_difference = 1, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-UCH',  @counted_qty = 65, @confirm_difference = 1, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-U6',   @counted_qty = 60, @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-UM2',  @counted_qty = 7,  @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-NOPE', @counted_qty = 5,  @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountA, @bin_code = 'ADJTEST-A1', @scanned_ref = 'ADJTEST-USHP', @counted_qty = 10, @user_id = @OpId;
    -- U9, UPK and UMV are deliberately not scanned

    EXEC warehouse.usp_count_finish_bin @count_id = @CountA, @bin_code = 'ADJTEST-A1', @user_id = @OpId;

    IF (SELECT COUNT(*) FROM warehouse.count_findings WHERE count_line_id = @LA1) <> 11
        RAISERROR('TEST SETUP FAILED: expected 11 findings from the count of A1.', 16, 1);

    -- The second count: B1, a quantity difference. It stays OPEN for now.
    EXEC warehouse.usp_count_open_bin @count_id = @CountB, @bin_code = 'ADJTEST-B1', @user_id = @OpId;
    EXEC warehouse.usp_count_scan_unit @count_id = @CountB, @bin_code = 'ADJTEST-B1', @scanned_ref = 'ADJTEST-UB', @counted_qty = 35, @confirm_difference = 1, @user_id = @OpId;
    EXEC warehouse.usp_count_finish_bin @count_id = @CountB, @bin_code = 'ADJTEST-B1', @user_id = @OpId;

    -- Count A is closed: unresolved findings, so it goes to REVIEW (A6 stays uncounted)
    EXEC warehouse.usp_count_close @count_id = @CountA, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountA) <> 'REVIEW'
        RAISERROR('TEST SETUP FAILED: the count of A should be in REVIEW.', 16, 1);

    DECLARE @FU2   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @U2);
    DECLARE @FU9   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @U9);
    DECLARE @FPk   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @UPk);
    DECLARE @FMv   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @UMv);
    DECLARE @FCh   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @UCh);
    DECLARE @FQ    INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @UQ);
    DECLARE @FBl   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @UBl);
    DECLARE @F6    INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @U6);
    DECLARE @FM2   INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.inventory_unit_id = @UM2);
    DECLARE @FNope INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.scanned_ref = 'ADJTEST-NOPE');
    DECLARE @FShp  INT = (SELECT f.finding_id FROM warehouse.count_findings f WHERE f.count_line_id = @LA1 AND f.scanned_ref = 'ADJTEST-USHP');
    DECLARE @FB    INT = (SELECT f.finding_id FROM warehouse.count_findings f
                          JOIN warehouse.count_lines l ON l.count_line_id = f.count_line_id
                          WHERE l.count_id = @CountB AND f.inventory_unit_id = @UB);

    -- The world moves on after the count (this is what the re-checks catch)
    UPDATE inventory.inventory_placements SET bin_id = @A6 WHERE inventory_unit_id = @UMv;   -- moved away
    UPDATE inventory.inventory_units      SET quantity = 61 WHERE inventory_unit_id = @UCh;  -- quantity drifted
    INSERT INTO warehouse.warehouse_tasks
        (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id, task_state_code, expires_at, created_by)
    VALUES ('PICK', @UM2, @A6, @A6, 'OPN', DATEADD(MINUTE, 5, SYSUTCDATETIME()), @UserId);          -- an open task

    -- Allocate UQ to an order (needs any existing party and ship-from address)
    DECLARE @PartyId INT = (SELECT TOP (1) party_id   FROM core.parties         ORDER BY party_id);
    DECLARE @AddrId  INT = (SELECT TOP (1) address_id FROM core.party_addresses ORDER BY address_id);
    DECLARE @HasAllocFixture BIT = CASE WHEN @PartyId IS NOT NULL AND @AddrId IS NOT NULL THEN 1 ELSE 0 END;

    IF @HasAllocFixture = 1
    BEGIN
        INSERT INTO outbound.shipments (shipment_ref, vehicle_ref, ship_from_address_id, shipment_status)
        VALUES ('ADJTEST-SHIP', 'ADJTEST-VEH', @AddrId, 'OPEN');
        DECLARE @AShipId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_orders (order_ref, customer_party_id, shipment_id, order_status_code)
        VALUES ('ADJTEST-ORD', @PartyId, @AShipId, 'ALLOCATED');
        DECLARE @AOrdId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_lines
            (outbound_order_id, line_no, sku_id, ordered_qty, allocated_qty, picked_qty, line_status_code)
        VALUES (@AOrdId, 1, @SkuId, 40, 40, 0, 'ALLOCATED');
        DECLARE @ALineId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_allocations
            (outbound_line_id, inventory_unit_id, allocated_qty, allocation_status)
        VALUES (@ALineId, @UQ, 40, 'PENDING');
    END

    ----------------------------------------------------------------
    -- 1. Permission: an operator is refused, and nothing changes
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_apply_finding @finding_id = @FU2, @action = 'APPLY', @user_id = @OpId, @result_code = @rc OUTPUT;

    IF @rc <> N'ERRPERM01'
        RAISERROR('FAIL: an operator was not refused with ERRPERM01 (counts.adjust).', 16, 1);

    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @U2) <> 20
       OR (SELECT resolution_code FROM warehouse.count_findings WHERE finding_id = @FU2) IS NOT NULL
        RAISERROR('FAIL: a refused operator changed a quantity or decided a finding.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id
               WHERE u.external_ref LIKE 'ADJTEST-%')
        RAISERROR('FAIL: a refused call wrote to the movement ledger.', 16, 1);

    PRINT 'PASS: counts.adjust is enforced - an operator is refused and nothing changes.';

    ----------------------------------------------------------------
    -- 2. State: only a count in REVIEW; bad input refused
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_apply_finding @finding_id = @FB, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;

    IF @rc <> N'ERRCNT21'
        RAISERROR('FAIL: a finding of a count still OPEN was not refused with ERRCNT21.', 16, 1);

    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @UB) <> 30
        RAISERROR('FAIL: a finding of an OPEN count was applied.', 16, 1);

    EXEC warehouse.usp_count_apply_finding @finding_id = @FU2, @action = 'FIX', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT25'
        RAISERROR('FAIL: a bad action was not refused with ERRCNT25.', 16, 1);

    EXEC warehouse.usp_count_apply_finding @finding_id = -1, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT20'
        RAISERROR('FAIL: a finding that does not exist was not refused with ERRCNT20.', 16, 1);

    PRINT 'PASS: only a count in REVIEW can be decided; a bad action and an unknown finding are refused.';

    ----------------------------------------------------------------
    -- 3. Apply a quantity difference
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_apply_finding @finding_id = @FU2, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;

    IF @rc <> N'SUCCNT20'
        RAISERROR('FAIL: a manager could not apply a quantity difference.', 16, 1);

    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @U2) <> 25
        RAISERROR('FAIL: applying a quantity difference did not set the quantity to what was counted (25).', 16, 1);

    DECLARE @MvU2 INT = (SELECT resolution_movement_id FROM warehouse.count_findings WHERE finding_id = @FU2);

    IF @MvU2 IS NULL
       OR NOT EXISTS (SELECT 1 FROM inventory.inventory_movements
                      WHERE movement_id = @MvU2 AND inventory_unit_id = @U2
                        AND movement_type = 'ADJUSTMENT' AND reference_type = 'COUNT' AND reference_id = @LA1
                        AND qty_before = 20 AND qty_after = 25 AND moved_qty = 5
                        AND from_bin_id = @A1 AND to_bin_id = @A1 AND moved_by_user_id = @MgrId)
        RAISERROR('FAIL: the ledger row for a quantity adjustment does not record qty_before 20 / qty_after 25 / moved_qty 5 against the finding.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE finding_id = @FU2 AND resolution_code = 'APPLIED' AND resolved_by = @MgrId AND resolved_at IS NOT NULL)
        RAISERROR('FAIL: an applied finding does not record who applied it, and when.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM inventory.v_movements
                   WHERE movement_id = @MvU2 AND qty_before = 20 AND qty_after = 25 AND reference_ref LIKE 'CNT-%')
        RAISERROR('FAIL: the movements view does not show the adjustment as CNT-nnnnnn with qty_before / qty_after.', 16, 1);

    -- Decided once: a second apply changes nothing
    EXEC warehouse.usp_count_apply_finding @finding_id = @FU2, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;

    IF @rc <> N'ERRCNT22'
        RAISERROR('FAIL: applying an already-applied finding was not refused with ERRCNT22.', 16, 1);

    IF (SELECT COUNT(*) FROM inventory.inventory_movements WHERE inventory_unit_id = @U2) <> 1
        RAISERROR('FAIL: applying twice wrote a second ledger row.', 16, 1);

    PRINT 'PASS: a quantity difference is applied once, with qty_before / qty_after on the ledger.';

    ----------------------------------------------------------------
    -- 4. Apply a MISSING pallet (scrapped as a count loss)
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_apply_finding @finding_id = @FU9, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;

    IF @rc <> N'SUCCNT20'
        RAISERROR('FAIL: a manager could not apply a MISSING finding.', 16, 1);

    IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @U9) <> 'SCR'
       OR EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @U9)
        RAISERROR('FAIL: a MISSING pallet was not scrapped (state SCR, no placement).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_movements m
                   JOIN warehouse.count_findings f ON f.resolution_movement_id = m.movement_id
                   WHERE f.finding_id = @FU9 AND m.inventory_unit_id = @U9
                     AND m.movement_type = 'ADJUSTMENT' AND m.reference_type = 'COUNT' AND m.reference_id = @LA1
                     AND m.from_bin_id = @A1 AND m.to_bin_id IS NULL
                     AND m.from_state_code = 'PTW' AND m.to_state_code = 'SCR'
                     AND m.qty_before IS NULL)
        RAISERROR('FAIL: the scrap ledger row does not record the bin it left (so it cannot be reversed).', 16, 1);

    PRINT 'PASS: a MISSING pallet is scrapped through the shared primitive, recording where it left.';

    ----------------------------------------------------------------
    -- 5. Apply a MISPLACED pallet (relocated by the move rules)
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_apply_finding @finding_id = @F6, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;

    IF @rc <> N'SUCCNT20'
        RAISERROR('FAIL: a manager could not apply a MISPLACED finding.', 16, 1);

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @U6) <> @A1
        RAISERROR('FAIL: a MISPLACED pallet was not relocated to the counted bin.', 16, 1);

    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @U6) <> 60
        RAISERROR('FAIL: relocating a misplaced pallet changed its quantity.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_movements m
                   JOIN warehouse.count_findings f ON f.resolution_movement_id = m.movement_id
                   WHERE f.finding_id = @F6 AND m.inventory_unit_id = @U6
                     AND m.movement_type = 'ADJUSTMENT' AND m.reference_type = 'COUNT' AND m.reference_id = @LA1
                     AND m.from_bin_id = @A6 AND m.to_bin_id = @A1
                     AND m.qty_before IS NULL AND m.qty_after IS NULL)
        RAISERROR('FAIL: the relocation ledger row does not record A6 -> A1 against the finding.', 16, 1);

    PRINT 'PASS: a MISPLACED pallet is relocated through the shared relocation, quantity untouched.';

    ----------------------------------------------------------------
    -- 6. Re-check: the world moved on since the count
    ----------------------------------------------------------------
    -- Blocked stock cannot have its quantity adjusted
    EXEC warehouse.usp_count_apply_finding @finding_id = @FBl, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT27'
        RAISERROR('FAIL: adjusting blocked (BL) stock was not refused with ERRCNT27.', 16, 1);
    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @UBl) <> 15
        RAISERROR('FAIL: a refused adjustment of blocked stock changed its quantity.', 16, 1);

    -- A pallet that is mid-flow cannot be written off from a count
    EXEC warehouse.usp_count_apply_finding @finding_id = @FPk, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT29'
        RAISERROR('FAIL: writing off a picked (PKD) pallet was not refused with ERRCNT29.', 16, 1);
    IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UPk) <> 'PKD'
       OR NOT EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @UPk)
        RAISERROR('FAIL: a refused write-off of a picked pallet changed it.', 16, 1);

    -- A pallet that moved away since the count
    EXEC warehouse.usp_count_apply_finding @finding_id = @FMv, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT26'
        RAISERROR('FAIL: scrapping a pallet that has moved since the count was not refused with ERRCNT26.', 16, 1);
    IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UMv) <> 'PTW'
        RAISERROR('FAIL: a pallet that had moved away was scrapped anyway.', 16, 1);

    -- A quantity that changed since the count
    EXEC warehouse.usp_count_apply_finding @finding_id = @FCh, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT26'
        RAISERROR('FAIL: applying over a quantity that changed since the count was not refused with ERRCNT26.', 16, 1);
    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @UCh) <> 61
        RAISERROR('FAIL: a quantity that had drifted was overwritten.', 16, 1);

    -- A pallet with an open task is not free to be relocated (the shared move rules)
    EXEC warehouse.usp_count_apply_finding @finding_id = @FM2, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRMOVE10'
        RAISERROR('FAIL: relocating a pallet with an open task was not refused with ERRMOVE10.', 16, 1);
    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UM2) <> @A6
        RAISERROR('FAIL: a pallet with an open task was relocated anyway.', 16, 1);

    -- A pallet allocated to an order
    IF @HasAllocFixture = 1
    BEGIN
        EXEC warehouse.usp_count_apply_finding @finding_id = @FQ, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
        IF @rc <> N'ERRCNT28'
            RAISERROR('FAIL: adjusting a pallet allocated to an order was not refused with ERRCNT28.', 16, 1);
        IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @UQ) <> 40
            RAISERROR('FAIL: a refused adjustment of an allocated pallet changed its quantity.', 16, 1);
    END
    ELSE
        PRINT 'SKIPPED: allocated-pallet check (no party / address in the database to hang an order on).';

    -- None of those refusals decided anything or touched the ledger
    IF EXISTS (SELECT 1 FROM warehouse.count_findings
               WHERE finding_id IN (@FBl, @FPk, @FMv, @FCh, @FM2) AND resolution_code IS NOT NULL)
        RAISERROR('FAIL: a refused apply left its finding decided.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_movements
               WHERE inventory_unit_id IN (@UBl, @UPk, @UMv, @UCh, @UM2, @UQ))
        RAISERROR('FAIL: a refused apply wrote to the movement ledger.', 16, 1);

    PRINT 'PASS: applying re-checks the world and refuses, changing nothing, with the right reason.';

    ----------------------------------------------------------------
    -- 7. Nothing to apply; decline needs a note
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_apply_finding @finding_id = @FNope, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT23'
        RAISERROR('FAIL: applying an UNKNOWN_UNIT finding was not refused with ERRCNT23.', 16, 1);

    EXEC warehouse.usp_count_apply_finding @finding_id = @FShp, @action = 'APPLY', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT23'
        RAISERROR('FAIL: applying a NOT_CORRECTED (shipped pallet) finding was not refused with ERRCNT23.', 16, 1);

    EXEC warehouse.usp_count_apply_finding @finding_id = @FBl, @action = 'DECLINE', @note = '   ', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT24'
        RAISERROR('FAIL: declining without a note was not refused with ERRCNT24.', 16, 1);

    IF (SELECT resolution_code FROM warehouse.count_findings WHERE finding_id = @FBl) IS NOT NULL
        RAISERROR('FAIL: a decline with no note decided the finding.', 16, 1);

    EXEC warehouse.usp_count_apply_finding @finding_id = @FBl, @action = 'decline',
         @note = 'Blocked stock - status to be changed first', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'SUCCNT21'
        RAISERROR('FAIL: declining with a note failed.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE finding_id = @FBl AND resolution_code = 'DECLINED' AND resolved_by = @MgrId
                     AND resolution_note = 'Blocked stock - status to be changed first'
                     AND resolution_movement_id IS NULL)
        RAISERROR('FAIL: a declined finding does not record who, why, and that no ledger row was written.', 16, 1);

    IF (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @UBl) <> 15
        RAISERROR('FAIL: declining a finding changed the stock record.', 16, 1);

    PRINT 'PASS: unknown / shipped findings have nothing to apply; a decline needs a note and changes no stock.';

    ----------------------------------------------------------------
    -- 8. Review: blocked while quantity / missing / misplaced findings are undecided
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_review @count_id = @CountA, @note = 'Done', @user_id = @MgrId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountA) <> 'REVIEW'
        RAISERROR('FAIL: a count with undecided quantity / missing / misplaced findings was marked reviewed.', 16, 1);

    -- Decide the rest: a manager and an admin, by declining with notes
    EXEC warehouse.usp_count_apply_finding @finding_id = @FPk, @action = 'DECLINE', @note = 'Picked pallet - handled in outbound', @user_id = @MgrId, @result_code = @rc OUTPUT;
    EXEC warehouse.usp_count_apply_finding @finding_id = @FMv, @action = 'DECLINE', @note = 'Pallet moved since the count',       @user_id = @MgrId, @result_code = @rc OUTPUT;
    EXEC warehouse.usp_count_apply_finding @finding_id = @FCh, @action = 'DECLINE', @note = 'Quantity changed since the count',   @user_id = @MgrId, @result_code = @rc OUTPUT;
    EXEC warehouse.usp_count_apply_finding @finding_id = @FQ,  @action = 'DECLINE', @note = 'Allocated - order to be re-picked',  @user_id = @MgrId, @result_code = @rc OUTPUT;
    EXEC warehouse.usp_count_apply_finding @finding_id = @FM2, @action = 'DECLINE', @note = 'Open task on the pallet',            @user_id = @AdmId, @result_code = @rc OUTPUT;

    IF @rc <> N'SUCCNT21'
        RAISERROR('FAIL: an admin could not decline a finding.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings WHERE finding_id = @FM2 AND resolution_code = 'DECLINED' AND resolved_by = @AdmId)
        RAISERROR('FAIL: the admin''s decision was not recorded as the admin''s.', 16, 1);

    -- Acknowledge the shipped pallet; the unknown one is left alone on purpose
    EXEC warehouse.usp_count_apply_finding @finding_id = @FShp, @action = 'DECLINE', @note = 'Shipment line to be checked by outbound', @user_id = @MgrId, @result_code = @rc OUTPUT;

    IF (SELECT findings_to_review FROM warehouse.v_count_sessions WHERE count_id = @CountA) <> 1
        RAISERROR('FAIL: only the unknown pallet should be left to review.', 16, 1);

    -- An unknown pallet left undecided does NOT block the review: the note covers it
    EXEC warehouse.usp_count_review @count_id = @CountA, @note = 'Stock adjusted; unknown pallet traced to a supplier mislabel', @user_id = @MgrId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountA) <> 'CLOSED'
        RAISERROR('FAIL: reviewing the count should end it CLOSED (bin A6 was left uncounted).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_sessions
                   WHERE count_id = @CountA AND reviewed_by = @MgrId AND reviewed_at IS NOT NULL)
        RAISERROR('FAIL: the review was not recorded.', 16, 1);

    -- Nothing can be decided once the count has been reviewed
    EXEC warehouse.usp_count_apply_finding @finding_id = @FNope, @action = 'DECLINE', @note = 'too late', @user_id = @MgrId, @result_code = @rc OUTPUT;
    IF @rc <> N'ERRCNT21'
        RAISERROR('FAIL: a finding of a reviewed count was not refused with ERRCNT21.', 16, 1);

    PRINT 'PASS: review waits for the decisions that matter, ignores unknown pallets, and closes the count to further decisions.';

    ----------------------------------------------------------------
    -- 9. A count that was still open can be decided once it is in REVIEW
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_close @count_id = @CountB, @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountB) <> 'REVIEW'
        RAISERROR('FAIL: the second count should be in REVIEW.', 16, 1);

    EXEC warehouse.usp_count_apply_finding @finding_id = @FB, @action = 'APPLY', @user_id = @AdmId, @result_code = @rc OUTPUT;

    IF @rc <> N'SUCCNT20' OR (SELECT quantity FROM inventory.inventory_units WHERE inventory_unit_id = @UB) <> 35
        RAISERROR('FAIL: an admin could not apply a quantity difference once its count was in REVIEW.', 16, 1);

    EXEC warehouse.usp_count_review @count_id = @CountB, @note = 'Quantity corrected', @user_id = @MgrId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountB) <> 'COMPLETE'
        RAISERROR('FAIL: a reviewed count with every bin counted should be COMPLETE.', 16, 1);

    PRINT 'PASS: a count can be decided once it is in REVIEW, and ends COMPLETE when every bin was counted.';

    ----------------------------------------------------------------
    -- 10. Regression: usp_write_off_unit now runs through usp_apply_scrap
    ----------------------------------------------------------------
    EXEC inventory.usp_write_off_unit
        @inventory_unit_id = @UExp, @reason = 'ADJTEST expired', @user_id = @UserId;

    IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UExp) <> 'SCR'
       OR EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id = @UExp)
        RAISERROR('FAIL: usp_write_off_unit no longer scraps a unit (state SCR, no placement).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_movements
                   WHERE inventory_unit_id = @UExp AND movement_type = 'ADJUSTMENT' AND reference_type = 'MANUAL'
                     AND from_bin_id = @A6 AND to_bin_id IS NULL
                     AND from_state_code = 'PTW' AND to_state_code = 'SCR')
        RAISERROR('FAIL: usp_write_off_unit no longer writes its ADJUSTMENT / MANUAL ledger row.', 16, 1);

    -- The primitive refuses a unit the state machine does not let be scrapped
    DECLARE @Thrown BIT = 0, @MvX INT;
    BEGIN TRY
        EXEC inventory.usp_apply_scrap
            @inventory_unit_id = @UPk, @reference_type = N'TEST', @reference_id = NULL,
            @user_id = @UserId, @session_id = NULL, @movement_id = @MvX OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Thrown = 1;
    END CATCH

    IF @Thrown = 0
        RAISERROR('FAIL: usp_apply_scrap scrapped a picked (PKD) unit the state machine does not allow.', 16, 1);

    IF (SELECT stock_state_code FROM inventory.inventory_units WHERE inventory_unit_id = @UPk) <> 'PKD'
        RAISERROR('FAIL: a refused usp_apply_scrap changed the unit.', 16, 1);

    PRINT 'PASS: usp_write_off_unit is unchanged in effect; the scrap primitive guards the state machine.';

    PRINT 'TEST PASSED: bin count adjustment.';

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
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE sc FROM warehouse.count_scans sc
    JOIN warehouse.count_lines l    ON l.count_line_id = sc.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE l FROM warehouse.count_lines l
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE s FROM warehouse.count_sessions s
    LEFT JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'ADJTEST-%'
       OR s.started_by IN (SELECT id FROM auth.users WHERE username LIKE 'adjtest[_]%');
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'ADJTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'ADJTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'ADJTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'ADJTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'ADJTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'ADJTEST-%';
DELETE FROM inventory.skus            WHERE sku_code LIKE 'ADJTEST-%';
DELETE FROM locations.bins            WHERE bin_code LIKE 'ADJTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'ADJTEST-%';
DELETE ur FROM auth.user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.username LIKE 'adjtest[_]%';
DELETE FROM auth.users                WHERE username LIKE 'adjtest[_]%';

IF @err IS NOT NULL
    RAISERROR(@err, 16, 1);
GO
