USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

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
