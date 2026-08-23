USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   Expiry / write-off reference data
   ------------------------------------------------------------
   Safe to run directly against a live database - every insert
   is guarded, so re-running this (or applying it via a full
   reset that also runs 010_tables.sql's own seed) is harmless.
   ============================================================ */

-- New terminal state: SCR (Scrapped) - mirrors SHP's pattern:
-- a real, unambiguous resting state rather than leaving a unit
-- in PTW forever with only a status flag doing the work.
IF NOT EXISTS (SELECT 1 FROM inventory.stock_states WHERE state_code = 'SCR')
    INSERT INTO inventory.stock_states (state_code, state_code_desc, is_terminal)
    VALUES ('SCR', 'SCRAPPED', 1);

-- Transitions into SCR - both require authority, matching the
-- LDD->PKD reversal precedent for hard-to-reverse actions
IF NOT EXISTS (
    SELECT 1 FROM inventory.stock_state_transitions
    WHERE from_state_code = 'PTW' AND to_state_code = 'SCR'
)
    INSERT INTO inventory.stock_state_transitions (from_state_code, to_state_code, requires_authority, notes)
    VALUES ('PTW', 'SCR', 1, 'Unit written off / scrapped');

IF NOT EXISTS (
    SELECT 1 FROM inventory.stock_state_transitions
    WHERE from_state_code = 'RCD' AND to_state_code = 'SCR'
)
    INSERT INTO inventory.stock_state_transitions (from_state_code, to_state_code, requires_authority, notes)
    VALUES ('RCD', 'SCR', 1, 'Unit rejected before putaway / scrapped');

-- New status: EX (Expired) - a computed fact surfaced by the
-- sweep job, not a status anything decides on the spot
IF NOT EXISTS (SELECT 1 FROM inventory.stock_statuses WHERE status_code = 'EX')
    INSERT INTO inventory.stock_statuses (status_code, status_desc)
    VALUES ('EX', 'EXPIRED');

-- Operation rules for PTW/EX - can still be moved (e.g. to a
-- scrap area later) but cannot be allocated or shipped without
-- an explicit override
IF NOT EXISTS (
    SELECT 1 FROM inventory.stock_operation_rules
    WHERE state_code = 'PTW' AND status_code = 'EX'
)
    INSERT INTO inventory.stock_operation_rules
        (state_code, status_code, can_move, can_allocate, can_ship, can_adjust, requires_override)
    VALUES ('PTW', 'EX', 1, 0, 0, 1, 1);

GO
PRINT 'Expiry / write-off reference data seeded.';
GO
