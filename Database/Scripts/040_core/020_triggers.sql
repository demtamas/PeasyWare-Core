CREATE OR ALTER TRIGGER core.tr_parties_audit
ON core.parties
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.party_changes
    (
        party_id,
        action,
        details,
        changed_by,
        session_id
    )
    SELECT
        COALESCE(i.party_id, d.party_id),

        CASE
            WHEN d.party_id IS NULL THEN 'CREATE_PARTY'
            WHEN i.party_id IS NULL THEN 'DELETE_PARTY'
            WHEN d.is_active <> i.is_active THEN 'SET_ACTIVE'
            ELSE 'UPDATE_PARTY'
        END,

        CONCAT(
            'code=', COALESCE(i.party_code, d.party_code),
            '; name=', COALESCE(i.display_name, d.display_name)
        ),

        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)

    FROM inserted i
    FULL JOIN deleted d
        ON d.party_id = i.party_id;
END;
GO
