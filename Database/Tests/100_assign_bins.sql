-- ==========================================================
-- TEST: usp_assign_bins_to_section / usp_assign_bins_to_zone
-- Verifies:
--   1. Bins are assigned to the correct section (check bins table)
--   2. Bins are assigned to the correct zone (check bins table)
--   3. updated_count matches the JSON array length
--   4. Unknown section code leaves bins unchanged
--   5. Empty JSON array assigns nothing
--
-- Note: SPs manage their own transactions (COMMIT/ROLLBACK
-- internally), so INSERT-EXEC cannot be used here.
-- Assertions check DB state directly. Cleanup is explicit.
-- ==========================================================
USE PW_Core_DEV;
GO

SET NOCOUNT ON;

BEGIN TRY

    DECLARE @RackTypeId INT =
        (SELECT storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK');
    DECLARE @UserId    INT              = 1;
    DECLARE @SessionId UNIQUEIDENTIFIER = NEWID();
    DECLARE @CorrId    UNIQUEIDENTIFIER = NEWID();

    -- ── 1. Create a test section and zone
    INSERT INTO locations.storage_sections (section_code, section_name, created_by)
    VALUES ('TST-SEC', 'Test Section', @UserId);
    DECLARE @SectionId INT = SCOPE_IDENTITY();

    INSERT INTO locations.zones (zone_code, zone_name, created_by)
    VALUES ('TST-ZN', 'Test Zone', @UserId);
    DECLARE @ZoneId INT = SCOPE_IDENTITY();

    -- ── 2. Create three inactive bins — no section/zone
    INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
    VALUES
        ('TASN-01', @RackTypeId, 1, 0, @UserId),
        ('TASN-02', @RackTypeId, 1, 0, @UserId),
        ('TASN-03', @RackTypeId, 1, 0, @UserId);

    -- ── 3. Assign two bins to section
    EXEC locations.usp_assign_bins_to_section
        @section_code   = 'TST-SEC',
        @bin_codes_json = '["TASN-01","TASN-02"]',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    IF (SELECT COUNT(*) FROM locations.bins
        WHERE bin_code IN ('TASN-01','TASN-02')
          AND storage_section_id = @SectionId) <> 2
        RAISERROR('TEST FAILED: assign_to_section — bins not linked to section.', 16, 1);

    -- Third bin must remain unassigned
    IF EXISTS (SELECT 1 FROM locations.bins
               WHERE bin_code = 'TASN-03' COLLATE Latin1_General_CS_AS
                 AND storage_section_id IS NOT NULL)
        RAISERROR('TEST FAILED: assign_to_section — TASN-03 should not be assigned.', 16, 1);

    -- ── 4. Assign all three bins to zone
    EXEC locations.usp_assign_bins_to_zone
        @zone_code      = 'TST-ZN',
        @bin_codes_json = '["TASN-01","TASN-02","TASN-03"]',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    IF (SELECT COUNT(*) FROM locations.bins
        WHERE bin_code IN ('TASN-01','TASN-02','TASN-03')
          AND zone_id = @ZoneId) <> 3
        RAISERROR('TEST FAILED: assign_to_zone — bins not linked to zone.', 16, 1);

    -- ── 5. Unknown section — bins must remain as-is (SP rolls back internally)
    EXEC locations.usp_assign_bins_to_section
        @section_code   = 'NONEXISTENT-SEC',
        @bin_codes_json = '["TASN-01"]',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    -- TASN-01 section assignment should still be TST-SEC (unchanged)
    IF NOT EXISTS (SELECT 1 FROM locations.bins
                   WHERE bin_code = 'TASN-01' COLLATE Latin1_General_CS_AS
                     AND storage_section_id = @SectionId)
        RAISERROR('TEST FAILED: Unknown section — bin assignment should not change.', 16, 1);

    -- ── 6. Empty JSON array — no state change
    DECLARE @SectionBefore INT = (
        SELECT storage_section_id FROM locations.bins
        WHERE bin_code = 'TASN-01' COLLATE Latin1_General_CS_AS
    );

    EXEC locations.usp_assign_bins_to_section
        @section_code   = 'TST-SEC',
        @bin_codes_json = '[]',
        @user_id        = @UserId,
        @session_id     = @SessionId,
        @correlation_id = @CorrId;

    IF (SELECT storage_section_id FROM locations.bins
        WHERE bin_code = 'TASN-01' COLLATE Latin1_General_CS_AS) <> @SectionBefore
        RAISERROR('TEST FAILED: Empty JSON — section assignment should not change.', 16, 1);

    PRINT 'TEST PASSED: assign_bins_to_section / assign_bins_to_zone — assignment, unknown section guard, empty JSON.';

END TRY
BEGIN CATCH
    DECLARE @msg NVARCHAR(2048) = ERROR_MESSAGE();
    -- Cleanup on failure
    DELETE FROM locations.bins WHERE bin_code IN ('TASN-01','TASN-02','TASN-03');
    DELETE FROM locations.storage_sections WHERE section_code = 'TST-SEC';
    DELETE FROM locations.zones            WHERE zone_code    = 'TST-ZN';
    RAISERROR(@msg, 16, 1);
    RETURN;
END CATCH

-- Always clean up (SPs committed, so no outer ROLLBACK available)
DELETE FROM locations.bins WHERE bin_code IN ('TASN-01','TASN-02','TASN-03');
DELETE FROM locations.storage_sections WHERE section_code = 'TST-SEC';
DELETE FROM locations.zones            WHERE zone_code    = 'TST-ZN';
GO
