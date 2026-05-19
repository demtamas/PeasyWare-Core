USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
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
GO
