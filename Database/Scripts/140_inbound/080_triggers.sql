*/
GO

CREATE OR ALTER TRIGGER inbound.tr_inbound_deliveries_audit
ON inbound.inbound_deliveries
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO audit.party_changes
    (
        party_id,
        action,
        details,
        changed_at,
        changed_by,
        session_id
    )
    SELECT
        -- Owner is the most stable auditing anchor
        COALESCE(i.owner_party_id, d.owner_party_id),

        CASE
            WHEN d.inbound_id IS NULL THEN 'CREATE_INBOUND'
            WHEN i.inbound_id IS NULL THEN 'DELETE_INBOUND'
            WHEN d.inbound_status <> i.inbound_status THEN 'INBOUND_STATUS_CHANGE'
            ELSE 'UPDATE_INBOUND_HEADER'
        END,

        CONCAT(
            'inbound_ref=', COALESCE(i.inbound_ref, d.inbound_ref),
            '; status=', COALESCE(i.inbound_status, d.inbound_status)
        ),

        SYSUTCDATETIME(),
        TRY_CAST(SESSION_CONTEXT(N'user_id') AS INT),
        TRY_CAST(SESSION_CONTEXT(N'session_id') AS UNIQUEIDENTIFIER)

    FROM inserted i
    FULL JOIN deleted d
        ON d.inbound_id = i.inbound_id;
END;
GO

CREATE OR ALTER TRIGGER inbound.trg_inbound_lines_guard
ON inbound.inbound_lines
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ---------------------------------------------------------------------
    -- 1) Block INSERT or DELETE after activation
    ---------------------------------------------------------------------
    IF (
           (EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted))
        OR (EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted))
       )
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM inbound.inbound_deliveries d
            JOIN inbound.inbound_lines l
                ON l.inbound_id = d.inbound_id
            WHERE l.inbound_line_id IN
            (
                SELECT inbound_line_id FROM inserted
                UNION
                SELECT inbound_line_id FROM deleted
            )
              AND d.inbound_status_code <> 'EXP'
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT01', 1;
        END

        RETURN;
    END

    ---------------------------------------------------------------------
    -- 2) UPDATE case – allow operational fields only
    ---------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM inbound.inbound_deliveries d
        JOIN inbound.inbound_lines l
            ON l.inbound_id = d.inbound_id
        WHERE l.inbound_line_id IN
        (
            SELECT inbound_line_id FROM inserted
            UNION
            SELECT inbound_line_id FROM deleted
        )
          AND d.inbound_status_code <> 'EXP'
    )
    BEGIN
        -- Block structural changes
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_line_id = i.inbound_line_id
            WHERE
                ISNULL(i.inbound_id,0) <> ISNULL(d.inbound_id,0)
             OR ISNULL(i.line_no,0) <> ISNULL(d.line_no,0)
             OR ISNULL(i.sku_id,0) <> ISNULL(d.sku_id,0)
             OR ISNULL(i.expected_qty,0) <> ISNULL(d.expected_qty,0)
             OR ISNULL(i.batch_number,'') <> ISNULL(d.batch_number,'')
             OR ISNULL(i.best_before_date,'19000101') <> ISNULL(d.best_before_date,'19000101')
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT01', 1;
        END

        -- Enforce allowed line state transitions
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_line_id = i.inbound_line_id
            WHERE ISNULL(i.line_state_code,'') <> ISNULL(d.line_state_code,'')
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM inbound.inbound_line_state_transitions t
                  WHERE t.from_state_code = d.line_state_code
                    AND t.to_state_code   = i.line_state_code
              )
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT01', 1;
        END
    END
END;
GO

/* =========================================================================================
   Trigger: inbound.trg_inbound_expected_units_guard
   Blocks structural modification of expected units after activation.
   Allows operational claim/receive updates in ACT/RCV/CLS, enforcing allowed transitions.
========================================================================================= */
CREATE OR ALTER TRIGGER inbound.trg_inbound_expected_units_guard
ON inbound.inbound_expected_units
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ---------------------------------------------------------------------
    -- 1) Block INSERT or DELETE after activation
    ---------------------------------------------------------------------
    IF (
           (EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted))
        OR (EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted))
       )
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM inbound.inbound_deliveries d
            JOIN inbound.inbound_lines l
                ON l.inbound_id = d.inbound_id
            WHERE l.inbound_line_id IN
            (
                SELECT inbound_line_id FROM inserted
                UNION
                SELECT inbound_line_id FROM deleted
            )
              AND d.inbound_status_code <> 'EXP'
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT02', 1;
        END

        RETURN;
    END

    ---------------------------------------------------------------------
    -- 2) UPDATE case – allow claim/receive fields only
    ---------------------------------------------------------------------
    IF EXISTS
    (
        SELECT 1
        FROM inbound.inbound_deliveries d
        JOIN inbound.inbound_lines l
            ON l.inbound_id = d.inbound_id
        WHERE l.inbound_line_id IN
        (
            SELECT inbound_line_id FROM inserted
            UNION
            SELECT inbound_line_id FROM deleted
        )
          AND d.inbound_status_code <> 'EXP'
    )
    BEGIN
        -- Block structural column changes
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_expected_unit_id = i.inbound_expected_unit_id
            WHERE
                ISNULL(i.inbound_line_id,0) <> ISNULL(d.inbound_line_id,0)
             OR ISNULL(i.expected_external_ref,'') <> ISNULL(d.expected_external_ref,'')
             OR ISNULL(i.expected_quantity,0) <> ISNULL(d.expected_quantity,0)
             OR ISNULL(i.batch_number,'') <> ISNULL(d.batch_number,'')
             OR ISNULL(i.best_before_date,'19000101') <> ISNULL(d.best_before_date,'19000101')
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT02', 1;
        END

        -- Enforce allowed expected unit state transitions
        IF EXISTS
        (
            SELECT 1
            FROM inserted i
            JOIN deleted d
              ON d.inbound_expected_unit_id = i.inbound_expected_unit_id
            WHERE ISNULL(i.expected_unit_state_code,'') <> ISNULL(d.expected_unit_state_code,'')
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM inbound.inbound_expected_unit_state_transitions t
                  WHERE t.from_state_code = d.expected_unit_state_code
                    AND t.to_state_code   = i.expected_unit_state_code
              )
        )
        BEGIN
            THROW 50001, 'ERRINBSTRUCT02', 1;
        END
    END
END;
GO

/* =========================================================================================
   Trigger: inbound.trg_inbound_mode_guard
   Prevents inbound_mode_code from being changed once set
========================================================================================= */
CREATE OR ALTER TRIGGER inbound.trg_inbound_mode_guard
ON inbound.inbound_deliveries
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN deleted d ON d.inbound_id = i.inbound_id
        WHERE d.inbound_mode_code IS NOT NULL
          AND i.inbound_mode_code <> d.inbound_mode_code
    )
    BEGIN
        THROW 50001, 'ERRINBMODE01', 1;
    END
END;
GO

CREATE INDEX IX_inbexp_outstanding
ON inbound.inbound_expected_units(expected_external_ref)
WHERE received_inventory_unit_id IS NULL;


/* ============================================================
   warehouse.warehouse_tasks
   ------------------------------------------------------------
   Operational work instructions for warehouse movements.
   One row = one actionable task for an operator.
   ============================================================ */
GO
