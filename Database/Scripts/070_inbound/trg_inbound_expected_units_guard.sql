USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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
GO
