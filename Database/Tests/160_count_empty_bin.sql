-- ==========================================================
-- TEST: Empty-bin count
--
--   Start:    snapshots exactly the empty bins (active, unlocked,
--             unoccupied, unreserved) - a locked, an inactive, an
--             occupied and a reserved bin are all excluded; starting
--             again RESUMES the open count (one open session, same lines)
--   Confirm:  scanning a bin marks it CONFIRMED_EMPTY; a bin that is not
--             in the count changes nothing; a bin the system filled since
--             the snapshot becomes OCCUPIED_SINCE, not confirmed empty
--   Report:   a pallet found in a "empty" bin has its recorded location
--             corrected (ledger row ADJUSTMENT / COUNT written) -
--             including BLOCKED stock; a second pallet into a full bin,
--             a picked pallet and a pallet with an open task are recorded
--             NOT_CORRECTED with the rule's code and left where they were;
--             an unknown SSCC is recorded and nothing is created; a pallet
--             the system already has in the bin adds nothing; a bin already
--             confirmed empty takes no findings
--             a pallet the system shows as SHIPPED or REVERSED is known, not
--             unknown: recorded NOT_CORRECTED with its own reason (ERRCNT06 /
--             ERRCNT07) and never brought back into stock; bin codes match
--             in any case
--   Close:    a count that found pallets it could not correct closes as REVIEW
--             (not COMPLETE); COMPLETE when nothing is pending and nothing to
--             review, CLOSED when bins remain and nothing to review
--   Review:   counts.review is enforced (operator refused; manager and admin
--             allowed), a note is required, only a REVIEW count can be
--             reviewed and only once, who / when / what is recorded, it ends
--             COMPLETE or CLOSED by the pending-bins check, and a count
--             waiting for review does NOT block a new count of that storage type
--
-- No outer transaction: the procedures roll back internally on their
-- refusal paths, so (as in 146 / 150) fixtures are cleaned explicitly.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

-- Pre-clean any leftovers from a previous aborted run.
DELETE f FROM warehouse.count_findings f
    JOIN warehouse.count_lines l    ON l.count_line_id = f.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'CNTTEST-%';
DELETE l FROM warehouse.count_lines l
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'CNTTEST-%';
DELETE s FROM warehouse.count_sessions s
    JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'CNTTEST-%';
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'CNTTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'CNTTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'CNTTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'CNTTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'CNTTEST-%';
DELETE FROM inventory.skus            WHERE sku_code = 'CNTTEST-SKU';
DELETE FROM locations.bins            WHERE bin_code LIKE 'CNTTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'CNTTEST-%';
DELETE ur FROM auth.user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.username LIKE 'cnttest[_]%';
DELETE FROM auth.users                WHERE username LIKE 'cnttest[_]%';
GO

DECLARE @err NVARCHAR(2048) = NULL;

BEGIN TRY

    DECLARE @UserId INT = (SELECT TOP (1) id FROM auth.users WHERE username = 'system');
    IF @UserId IS NULL
        RAISERROR('TEST SETUP FAILED: system user not found.', 16, 1);

    ----------------------------------------------------------------
    -- Fixture
    ----------------------------------------------------------------
    INSERT INTO locations.storage_types (storage_type_code, storage_type_name) VALUES
        ('CNTTEST-STYPE',  'Count Test Type'),
        ('CNTTEST-STYPE2', 'Count Test Type 2');

    DECLARE @St  INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'CNTTEST-STYPE');
    DECLARE @St2 INT = (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'CNTTEST-STYPE2');

    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, is_locked) VALUES
        ('CNTTEST-C1',    @St,  1,   1, 0),
        ('CNTTEST-C2',    @St,  1,   1, 0),
        ('CNTTEST-C3',    @St,  1,   1, 0),
        ('CNTTEST-C4',    @St,  1,   1, 0),
        ('CNTTEST-C5',    @St,  1,   1, 0),
        ('CNTTEST-C6',    @St,  1,   1, 1),   -- locked   : not empty-bin eligible
        ('CNTTEST-C7',    @St,  1,   0, 0),   -- inactive : not eligible
        ('CNTTEST-C8',    @St,  1,   1, 0),   -- occupied : not eligible
        ('CNTTEST-C9',    @St,  1,   1, 0),   -- reserved : not eligible
        ('CNTTEST-OTHER', @St2, 999, 1, 0);   -- where the "lost" pallets are recorded

    DECLARE @C1    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C1');
    DECLARE @C2    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C2');
    DECLARE @C3    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C3');
    DECLARE @C4    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C4');
    DECLARE @C5    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C5');
    DECLARE @C8    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C8');
    DECLARE @C9    INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-C9');
    DECLARE @Other INT = (SELECT bin_id FROM locations.bins WHERE bin_code = 'CNTTEST-OTHER');

    INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, preferred_storage_type_id)
    VALUES ('CNTTEST-SKU', 'Count Test SKU', '09999900001601', 'EA', @St);
    DECLARE @SkuId INT = (SELECT sku_id FROM inventory.skus WHERE sku_code = 'CNTTEST-SKU');

    INSERT INTO inventory.inventory_units (sku_id, external_ref, quantity, stock_state_code, stock_status_code) VALUES
        (@SkuId, 'CNTTEST-UFOUND',  10, 'PTW', 'AV'),
        (@SkuId, 'CNTTEST-USECOND', 10, 'PTW', 'AV'),
        (@SkuId, 'CNTTEST-UBLK',    10, 'PTW', 'BL'),
        (@SkuId, 'CNTTEST-UPKD',    10, 'PKD', 'AV'),
        (@SkuId, 'CNTTEST-UTASK',   10, 'PTW', 'AV'),
        (@SkuId, 'CNTTEST-ULATE',   10, 'PTW', 'AV'),
        (@SkuId, 'CNTTEST-UOCC',    10, 'PTW', 'AV'),
        (@SkuId, 'CNTTEST-USHP',    10, 'SHP', 'AV'),
        (@SkuId, 'CNTTEST-UREV',    10, 'REV', 'AV');

    INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id)
    SELECT u.inventory_unit_id,
           CASE WHEN u.external_ref = 'CNTTEST-UOCC' THEN @C8 ELSE @Other END
    FROM inventory.inventory_units u
    WHERE u.external_ref LIKE 'CNTTEST-%'
      AND u.stock_state_code NOT IN ('SHP', 'REV');   -- shipped / reversed units hold no placement

    DECLARE @UFound  INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-UFOUND');
    DECLARE @USecond INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-USECOND');
    DECLARE @UBlk    INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-UBLK');
    DECLARE @UPkd    INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-UPKD');
    DECLARE @UTask   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-UTASK');
    DECLARE @ULate   INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-ULATE');
    DECLARE @UShp    INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-USHP');
    DECLARE @URev    INT = (SELECT inventory_unit_id FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-UREV');

    -- C9 has stock on its way (unexpired reservation)
    INSERT INTO locations.bin_reservations (bin_id, reservation_type, reserved_by, expires_at)
    VALUES (@C9, 'MOVE', @UserId, DATEADD(MINUTE, 5, SYSUTCDATETIME()));

    -- UTASK has an open task, so it is not free to be moved
    INSERT INTO warehouse.warehouse_tasks
        (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id,
         task_state_code, expires_at, created_by)
    VALUES
        ('PICK', @UTask, @Other, @Other, 'OPN', DATEADD(MINUTE, 5, SYSUTCDATETIME()), @UserId);

    -- USHP left on a delivery: shipment + order + picked allocation + SHIP
    -- movement, so its finding can say WHERE it went. Needs any existing party
    -- and ship-from address to hang the shipment and order on.
    DECLARE @PartyId INT = (SELECT TOP (1) party_id   FROM core.parties        ORDER BY party_id);
    DECLARE @AddrId  INT = (SELECT TOP (1) address_id FROM core.party_addresses ORDER BY address_id);
    DECLARE @HasShipFixture BIT = CASE WHEN @PartyId IS NOT NULL AND @AddrId IS NOT NULL THEN 1 ELSE 0 END;

    IF @HasShipFixture = 1
    BEGIN
        INSERT INTO outbound.shipments
            (shipment_ref, vehicle_ref, ship_from_address_id, actual_departure, shipment_status)
        VALUES
            ('CNTTEST-SHIP', 'CNTTEST-VEH', @AddrId, '2026-09-11T18:30:00', 'DEPARTED');
        DECLARE @ShipId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_orders
            (order_ref, customer_party_id, shipment_id, order_status_code)
        VALUES
            ('CNTTEST-ORD', @PartyId, @ShipId, 'SHIPPED');
        DECLARE @OrdId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_lines
            (outbound_order_id, line_no, sku_id, ordered_qty, allocated_qty, picked_qty, line_status_code)
        VALUES
            (@OrdId, 1, @SkuId, 10, 10, 10, 'PICKED');
        DECLARE @LineId INT = SCOPE_IDENTITY();

        INSERT INTO outbound.outbound_allocations
            (outbound_line_id, inventory_unit_id, allocated_qty, allocation_status)
        VALUES
            (@LineId, @UShp, 10, 'PICKED');

        INSERT INTO inventory.inventory_movements
            (inventory_unit_id, sku_id, moved_qty, from_bin_id, to_bin_id,
             from_state_code, to_state_code, from_status_code, to_status_code,
             movement_type, reference_type, reference_id, moved_at, moved_by_user_id)
        VALUES
            (@UShp, @SkuId, 10, @Other, NULL,
             'LDD', 'SHP', 'AV', 'AV',
             'SHIP', 'SHIPMENT', @ShipId, '2026-09-11T18:30:00', @UserId);
    END

    -- Reviewers: one of each role, so counts.review is proven for the roles that
    -- should have it (manager, admin) and refused for the one that should not
    DECLARE @OpRole  INT = (SELECT id FROM auth.roles WHERE role_name = 'operator');
    DECLARE @MgrRole INT = (SELECT id FROM auth.roles WHERE role_name = 'manager');
    DECLARE @AdmRole INT = (SELECT id FROM auth.roles WHERE role_name = 'admin');

    IF @OpRole IS NULL OR @MgrRole IS NULL OR @AdmRole IS NULL
        RAISERROR('TEST SETUP FAILED: operator / manager / admin role not found.', 16, 1);

    INSERT INTO auth.users (username, display_name, email, salt, is_active) VALUES
        ('cnttest_operator', 'Count Test Operator (temp)', 'cnttest_operator@pw.local', 0x00, 1),
        ('cnttest_manager',  'Count Test Manager (temp)',  'cnttest_manager@pw.local',  0x00, 1),
        ('cnttest_admin',    'Count Test Admin (temp)',    'cnttest_admin@pw.local',    0x00, 1);

    DECLARE @OpId  INT = (SELECT id FROM auth.users WHERE username = 'cnttest_operator');
    DECLARE @MgrId INT = (SELECT id FROM auth.users WHERE username = 'cnttest_manager');
    DECLARE @AdmId INT = (SELECT id FROM auth.users WHERE username = 'cnttest_admin');

    INSERT INTO auth.user_roles (user_id, role_id) VALUES
        (@OpId,  @OpRole),
        (@MgrId, @MgrRole),
        (@AdmId, @AdmRole);

    ----------------------------------------------------------------
    -- 1. Start: snapshot is exactly the eligible empty bins
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_start_empty_bin
        @storage_type_code = 'CNTTEST-STYPE', @user_id = @UserId;

    DECLARE @CountId INT = (SELECT count_id FROM warehouse.count_sessions
                            WHERE storage_type_id = @St AND status_code = 'OPEN');
    IF @CountId IS NULL
        RAISERROR('FAIL: starting a count did not create an OPEN session.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_lines WHERE count_id = @CountId) <> 5
        RAISERROR('FAIL: the snapshot should hold exactly the 5 eligible empty bins.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_lines l
               JOIN locations.bins b ON b.bin_id = l.bin_id
               WHERE l.count_id = @CountId
                 AND b.bin_code IN ('CNTTEST-C6', 'CNTTEST-C7', 'CNTTEST-C8', 'CNTTEST-C9', 'CNTTEST-OTHER'))
        RAISERROR('FAIL: a locked / inactive / occupied / reserved bin was snapshotted as empty.', 16, 1);

    -- Starting again resumes, it does not duplicate
    EXEC warehouse.usp_count_start_empty_bin
        @storage_type_code = 'CNTTEST-STYPE', @user_id = @UserId;

    IF (SELECT COUNT(*) FROM warehouse.count_sessions WHERE storage_type_id = @St AND status_code = 'OPEN') <> 1
        RAISERROR('FAIL: starting again created a second OPEN count instead of resuming.', 16, 1);

    IF (SELECT COUNT(*) FROM warehouse.count_lines WHERE count_id = @CountId) <> 5
        RAISERROR('FAIL: resuming changed the count''s lines.', 16, 1);

    DECLARE @L1 INT = (SELECT l.count_line_id FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id WHERE l.count_id = @CountId AND b.bin_code = 'CNTTEST-C1');
    DECLARE @L2 INT = (SELECT l.count_line_id FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id WHERE l.count_id = @CountId AND b.bin_code = 'CNTTEST-C2');
    DECLARE @L3 INT = (SELECT l.count_line_id FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id WHERE l.count_id = @CountId AND b.bin_code = 'CNTTEST-C3');
    DECLARE @L4 INT = (SELECT l.count_line_id FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id WHERE l.count_id = @CountId AND b.bin_code = 'CNTTEST-C4');
    DECLARE @L5 INT = (SELECT l.count_line_id FROM warehouse.count_lines l JOIN locations.bins b ON b.bin_id = l.bin_id WHERE l.count_id = @CountId AND b.bin_code = 'CNTTEST-C5');

    PRINT 'PASS: start snapshots exactly the empty bins, and resumes an open count.';

    ----------------------------------------------------------------
    -- 2. Confirm empty
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_confirm_empty
        @count_id = @CountId, @bin_code = 'CNTTEST-C1', @user_id = @UserId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @L1) <> 'CONFIRMED_EMPTY'
        RAISERROR('FAIL: scanning an empty bin did not mark it CONFIRMED_EMPTY.', 16, 1);

    IF (SELECT counted_by FROM warehouse.count_lines WHERE count_line_id = @L1) <> @UserId
        RAISERROR('FAIL: the counter was not recorded on the line.', 16, 1);

    -- A bin that is not in the count changes nothing
    EXEC warehouse.usp_count_confirm_empty
        @count_id = @CountId, @bin_code = 'CNTTEST-C6', @user_id = @UserId;

    IF (SELECT COUNT(*) FROM warehouse.count_lines
        WHERE count_id = @CountId AND line_status_code <> 'PENDING') <> 1
        RAISERROR('FAIL: confirming a bin outside the count altered the count.', 16, 1);

    -- Counted twice stays counted once
    EXEC warehouse.usp_count_confirm_empty
        @count_id = @CountId, @bin_code = 'CNTTEST-C1', @user_id = @UserId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @L1) <> 'CONFIRMED_EMPTY'
        RAISERROR('FAIL: re-confirming a counted bin changed its status.', 16, 1);

    PRINT 'PASS: confirm marks the line, ignores other bins, and is not repeatable.';

    ----------------------------------------------------------------
    -- 3. Occupied since the snapshot
    ----------------------------------------------------------------
    UPDATE inventory.inventory_placements SET bin_id = @C2 WHERE inventory_unit_id = @ULate;

    EXEC warehouse.usp_count_confirm_empty
        @count_id = @CountId, @bin_code = 'CNTTEST-C2', @user_id = @UserId;

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @L2) <> 'OCCUPIED_SINCE'
        RAISERROR('FAIL: a bin the system filled since the snapshot was confirmed empty.', 16, 1);

    PRINT 'PASS: a bin filled since the snapshot becomes OCCUPIED_SINCE.';

    ----------------------------------------------------------------
    -- 4. Report stock
    ----------------------------------------------------------------
    -- A bin already confirmed empty takes no findings
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C1', @scanned_ref = 'CNTTEST-USECOND', @user_id = @UserId;

    IF EXISTS (SELECT 1 FROM warehouse.count_findings WHERE count_line_id = @L1)
        RAISERROR('FAIL: a finding was recorded against a bin already confirmed empty.', 16, 1);

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @USecond) <> @Other
        RAISERROR('FAIL: a refused report moved a pallet.', 16, 1);

    -- Found, movable: record corrected
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C3', @scanned_ref = 'CNTTEST-UFOUND', @user_id = @UserId;

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UFound) <> @C3
        RAISERROR('FAIL: a pallet found in the bin was not relocated to it in the system.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L3 AND inventory_unit_id = @UFound
                     AND finding_code = 'RECORD_CORRECTED' AND previous_bin_id = @Other
                     AND movement_id IS NOT NULL)
        RAISERROR('FAIL: the correction was not recorded as RECORD_CORRECTED with its ledger row.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM inventory.inventory_movements
                   WHERE inventory_unit_id = @UFound AND from_bin_id = @Other AND to_bin_id = @C3
                     AND movement_type = 'ADJUSTMENT' AND reference_type = 'COUNT' AND reference_id = @L3)
        RAISERROR('FAIL: the ledger row is not ADJUSTMENT / COUNT for the count line.', 16, 1);

    IF (SELECT line_status_code FROM warehouse.count_lines WHERE count_line_id = @L3) <> 'STOCK_FOUND'
        RAISERROR('FAIL: the line was not marked STOCK_FOUND.', 16, 1);

    -- Second pallet into the same capacity-1 bin: not corrected, left where it was
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C3', @scanned_ref = 'CNTTEST-USECOND', @user_id = @UserId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L3 AND inventory_unit_id = @USecond
                     AND finding_code = 'NOT_CORRECTED' AND reason_code = 'ERRMOVE09')
        RAISERROR('FAIL: a pallet the bin cannot take was not recorded NOT_CORRECTED / ERRMOVE09.', 16, 1);

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @USecond) <> @Other
        RAISERROR('FAIL: a NOT_CORRECTED pallet was moved anyway.', 16, 1);

    -- Same pallet again: the system already has it here - nothing new recorded
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C3', @scanned_ref = 'CNTTEST-UFOUND', @user_id = @UserId;

    IF (SELECT COUNT(*) FROM warehouse.count_findings WHERE count_line_id = @L3) <> 2
        RAISERROR('FAIL: re-scanning a pallet the system already has here added a finding.', 16, 1);

    -- Blocked stock is correctable
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C4', @scanned_ref = 'CNTTEST-UBLK', @user_id = @UserId;

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UBlk) <> @C4
        RAISERROR('FAIL: blocked (BL) stock found in a bin was not relocated to it.', 16, 1);

    -- Unknown SSCC, picked pallet, pallet with an open task - all on C5
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C5', @scanned_ref = 'CNTTEST-NOPE', @user_id = @UserId;
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C5', @scanned_ref = 'CNTTEST-UPKD', @user_id = @UserId;
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'CNTTEST-C5', @scanned_ref = 'CNTTEST-UTASK', @user_id = @UserId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L5 AND scanned_ref = 'CNTTEST-NOPE'
                     AND finding_code = 'UNKNOWN_UNIT' AND inventory_unit_id IS NULL)
        RAISERROR('FAIL: an unknown SSCC was not recorded as UNKNOWN_UNIT.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_units WHERE external_ref = 'CNTTEST-NOPE')
        RAISERROR('FAIL: an unknown SSCC caused a unit to be created.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L5 AND inventory_unit_id = @UPkd
                     AND finding_code = 'NOT_CORRECTED' AND reason_code = 'ERRMOVE02')
        RAISERROR('FAIL: a picked pallet was not recorded NOT_CORRECTED / ERRMOVE02.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L5 AND inventory_unit_id = @UTask
                     AND finding_code = 'NOT_CORRECTED' AND reason_code = 'ERRMOVE10')
        RAISERROR('FAIL: a pallet with an open task was not recorded NOT_CORRECTED / ERRMOVE10.', 16, 1);

    IF (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UPkd) <> @Other
       OR (SELECT bin_id FROM inventory.inventory_placements WHERE inventory_unit_id = @UTask) <> @Other
        RAISERROR('FAIL: a NOT_CORRECTED pallet was moved anyway.', 16, 1);

    -- A shipped pallet and a reversed one are KNOWN to the system: found,
    -- recorded with the reason, and never brought back into stock. The bin
    -- code is typed in lowercase on purpose - it must still match.
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'cnttest-c5', @scanned_ref = 'CNTTEST-USHP', @user_id = @UserId;
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId, @bin_code = 'cnttest-c5', @scanned_ref = 'CNTTEST-UREV', @user_id = @UserId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L5 AND inventory_unit_id = @UShp
                     AND finding_code = 'NOT_CORRECTED' AND reason_code = 'ERRCNT06')
        RAISERROR('FAIL: a shipped pallet was not recorded NOT_CORRECTED / ERRCNT06 (or the lowercase bin code did not match).', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_findings
                   WHERE count_line_id = @L5 AND inventory_unit_id = @URev
                     AND finding_code = 'NOT_CORRECTED' AND reason_code = 'ERRCNT07')
        RAISERROR('FAIL: a reversed pallet was not recorded NOT_CORRECTED / ERRCNT07.', 16, 1);

    IF EXISTS (SELECT 1 FROM warehouse.count_findings
               WHERE scanned_ref IN ('CNTTEST-USHP', 'CNTTEST-UREV') AND finding_code = 'UNKNOWN_UNIT')
        RAISERROR('FAIL: a shipped or reversed pallet was reported as unknown.', 16, 1);

    IF EXISTS (SELECT 1 FROM inventory.inventory_placements WHERE inventory_unit_id IN (@UShp, @URev))
        RAISERROR('FAIL: a count brought a shipped or reversed pallet back into stock.', 16, 1);

    -- ... and the shipped pallet's finding says WHICH delivery and order it left on
    IF @HasShipFixture = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM warehouse.v_count_findings
                       WHERE inventory_unit_id = @UShp
                         AND shipment_ref = 'CNTTEST-SHIP'
                         AND vehicle_ref  = 'CNTTEST-VEH'
                         AND shipped_at   = '2026-09-11T18:30:00'
                         AND order_ref    = 'CNTTEST-ORD'
                         AND customer_name IS NOT NULL)
            RAISERROR('FAIL: the finding for a shipped pallet does not name the delivery and order it left on.', 16, 1);

        PRINT 'PASS: a shipped pallet''s finding names the delivery and order it left on.';
    END
    ELSE
        PRINT 'SKIPPED: delivery details check (no party / address in the database to hang a shipment on).';

    PRINT 'PASS: report corrects what the move rules allow and records the rest untouched.';

    ----------------------------------------------------------------
    -- 5. Close: a count that found something goes to REVIEW, not COMPLETE
    ----------------------------------------------------------------
    IF EXISTS (SELECT 1 FROM warehouse.count_lines WHERE count_id = @CountId AND line_status_code = 'PENDING')
        RAISERROR('FAIL (setup): bins are still pending before the first close.', 16, 1);

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId) <> 'OPEN'
        RAISERROR('FAIL: the count should stay OPEN until it is explicitly closed.', 16, 1);

    EXEC warehouse.usp_count_close @count_id = @CountId, @user_id = @UserId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId) <> 'REVIEW'
        RAISERROR('FAIL: a count that found pallets it could not correct should close as REVIEW, not COMPLETE.', 16, 1);

    IF (SELECT findings_to_review FROM warehouse.v_count_sessions WHERE count_id = @CountId) < 1
        RAISERROR('FAIL: the count view does not report findings awaiting review.', 16, 1);

    PRINT 'PASS: a count with uncorrected findings closes as REVIEW.';

    ----------------------------------------------------------------
    -- 5b. Review: permission, note, state, and who / when / what recorded
    ----------------------------------------------------------------
    -- An operator may not review
    EXEC warehouse.usp_count_review
        @count_id = @CountId, @note = 'operator trying it on', @user_id = @OpId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId) <> 'REVIEW'
        RAISERROR('FAIL: an operator was able to mark a count reviewed (counts.review).', 16, 1);

    -- A manager has to say what was done
    EXEC warehouse.usp_count_review
        @count_id = @CountId, @note = '   ', @user_id = @MgrId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId) <> 'REVIEW'
        RAISERROR('FAIL: a review with no note was accepted.', 16, 1);

    -- A manager with a note: reviewed. Every bin was visited, so it ends COMPLETE
    EXEC warehouse.usp_count_review
        @count_id = @CountId, @note = 'Shipment line reversed; pallet received back', @user_id = @MgrId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId) <> 'COMPLETE'
        RAISERROR('FAIL: reviewing a count with no bins pending should end it COMPLETE.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_sessions
                   WHERE count_id = @CountId AND reviewed_by = @MgrId AND reviewed_at IS NOT NULL
                     AND review_note = 'Shipment line reversed; pallet received back')
        RAISERROR('FAIL: the reviewer, time and note were not recorded on the count.', 16, 1);

    -- It cannot be reviewed twice, and the first review is not overwritten
    EXEC warehouse.usp_count_review
        @count_id = @CountId, @note = 'second opinion', @user_id = @AdmId;

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_sessions
                   WHERE count_id = @CountId AND reviewed_by = @MgrId
                     AND review_note = 'Shipment line reversed; pallet received back')
        RAISERROR('FAIL: a second review overwrote the first.', 16, 1);

    PRINT 'PASS: review needs counts.review and a note, records who / when / what, and cannot be repeated.';

    ----------------------------------------------------------------
    -- 6. Close with bins pending: CLOSED
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_start_empty_bin
        @storage_type_code = 'CNTTEST-STYPE', @user_id = @UserId;

    DECLARE @CountId2 INT = (SELECT count_id FROM warehouse.count_sessions
                             WHERE storage_type_id = @St AND status_code = 'OPEN');

    IF @CountId2 IS NULL OR @CountId2 = @CountId
        RAISERROR('FAIL: a new count could not be started once the previous one was closed.', 16, 1);

    -- C1 and C5 are the only bins still empty (C2/C3/C4 now hold pallets)
    IF (SELECT COUNT(*) FROM warehouse.count_lines WHERE count_id = @CountId2) <> 2
        RAISERROR('FAIL: the second count should snapshot only the 2 bins still empty.', 16, 1);

    EXEC warehouse.usp_count_close @count_id = @CountId2, @user_id = @UserId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId2) <> 'CLOSED'
        RAISERROR('FAIL: closing a count with bins pending should give CLOSED.', 16, 1);

    PRINT 'PASS: a count with nothing to review closes as CLOSED when bins remain.';

    ----------------------------------------------------------------
    -- 7. REVIEW with bins still pending: a new count is not blocked,
    --    and the review (by an admin) ends it CLOSED, not COMPLETE
    ----------------------------------------------------------------
    EXEC warehouse.usp_count_start_empty_bin
        @storage_type_code = 'CNTTEST-STYPE', @user_id = @UserId;

    DECLARE @CountId3 INT = (SELECT count_id FROM warehouse.count_sessions
                             WHERE storage_type_id = @St AND status_code = 'OPEN');

    IF @CountId3 IS NULL OR @CountId3 IN (@CountId, @CountId2)
        RAISERROR('FAIL (setup): the third count could not be started.', 16, 1);

    -- An unknown pallet in C5; C1 deliberately left pending
    EXEC warehouse.usp_count_report_stock
        @count_id = @CountId3, @bin_code = 'CNTTEST-C5', @scanned_ref = 'CNTTEST-NOPE2', @user_id = @UserId;

    EXEC warehouse.usp_count_close @count_id = @CountId3, @user_id = @UserId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId3) <> 'REVIEW'
        RAISERROR('FAIL: a count with an unknown pallet should close as REVIEW even with bins still pending.', 16, 1);

    -- A count waiting for review does NOT block a new count of the same storage
    -- type (only an OPEN one does), or nobody could count it again until review
    EXEC warehouse.usp_count_start_empty_bin
        @storage_type_code = 'CNTTEST-STYPE', @user_id = @UserId;

    DECLARE @CountId4 INT = (SELECT count_id FROM warehouse.count_sessions
                             WHERE storage_type_id = @St AND status_code = 'OPEN');

    IF @CountId4 IS NULL OR @CountId4 = @CountId3
        RAISERROR('FAIL: a count waiting for review blocked a new count of the same storage type.', 16, 1);

    EXEC warehouse.usp_count_close @count_id = @CountId4, @user_id = @UserId;

    -- An admin reviews #3: bins were left uncounted, so it ends CLOSED
    EXEC warehouse.usp_count_review
        @count_id = @CountId3, @note = 'Unknown pallet traced to a supplier mislabel', @user_id = @AdmId;

    IF (SELECT status_code FROM warehouse.count_sessions WHERE count_id = @CountId3) <> 'CLOSED'
        RAISERROR('FAIL: reviewing a count with bins left uncounted should end it CLOSED.', 16, 1);

    IF NOT EXISTS (SELECT 1 FROM warehouse.count_sessions
                   WHERE count_id = @CountId3 AND reviewed_by = @AdmId AND reviewed_at IS NOT NULL)
        RAISERROR('FAIL: the admin review was not recorded.', 16, 1);

    -- A count that never needed review cannot be reviewed
    EXEC warehouse.usp_count_review
        @count_id = @CountId4, @note = 'not needed', @user_id = @AdmId;

    IF EXISTS (SELECT 1 FROM warehouse.count_sessions WHERE count_id = @CountId4 AND reviewed_at IS NOT NULL)
        RAISERROR('FAIL: a count that never needed review was marked reviewed.', 16, 1);

    PRINT 'PASS: REVIEW does not block a new count, and a reviewed count with bins left ends CLOSED.';

    PRINT 'TEST PASSED: empty-bin count.';

END TRY
BEGIN CATCH
    SET @err = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK;
END CATCH

-- Cleanup (always runs)
DELETE f FROM warehouse.count_findings f
    JOIN warehouse.count_lines l    ON l.count_line_id = f.count_line_id
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'CNTTEST-%';
DELETE l FROM warehouse.count_lines l
    JOIN warehouse.count_sessions s ON s.count_id = l.count_id
    JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'CNTTEST-%';
DELETE s FROM warehouse.count_sessions s
    JOIN locations.storage_types st ON st.storage_type_id = s.storage_type_id
    WHERE st.storage_type_code LIKE 'CNTTEST-%';
DELETE r FROM locations.bin_reservations r JOIN locations.bins b ON b.bin_id = r.bin_id WHERE b.bin_code LIKE 'CNTTEST-%';
DELETE t FROM warehouse.warehouse_tasks t JOIN inventory.inventory_units u ON u.inventory_unit_id = t.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE m FROM inventory.inventory_movements m JOIN inventory.inventory_units u ON u.inventory_unit_id = m.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE p FROM inventory.inventory_placements p JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE a FROM outbound.outbound_allocations a JOIN inventory.inventory_units u ON u.inventory_unit_id = a.inventory_unit_id WHERE u.external_ref LIKE 'CNTTEST-%';
DELETE ol FROM outbound.outbound_lines ol JOIN outbound.outbound_orders o ON o.outbound_order_id = ol.outbound_order_id WHERE o.order_ref LIKE 'CNTTEST-%';
DELETE FROM outbound.outbound_orders WHERE order_ref LIKE 'CNTTEST-%';
DELETE FROM outbound.shipments        WHERE shipment_ref LIKE 'CNTTEST-%';
DELETE FROM inventory.inventory_units WHERE external_ref LIKE 'CNTTEST-%';
DELETE FROM inventory.skus            WHERE sku_code = 'CNTTEST-SKU';
DELETE FROM locations.bins            WHERE bin_code LIKE 'CNTTEST-%';
DELETE FROM locations.storage_types   WHERE storage_type_code LIKE 'CNTTEST-%';
DELETE ur FROM auth.user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.username LIKE 'cnttest[_]%';
DELETE FROM auth.users                WHERE username LIKE 'cnttest[_]%';

IF @err IS NOT NULL
    RAISERROR(@err, 16, 1);
GO
