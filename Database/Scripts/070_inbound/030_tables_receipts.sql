USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE inbound.inbound_receipts
(
    receipt_id              INT IDENTITY(1,1)
                            CONSTRAINT PK_inbound_receipts
                            PRIMARY KEY,

    inbound_line_id         INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_line
                            REFERENCES inbound.inbound_lines(inbound_line_id),

    inbound_expected_unit_id INT NULL
                            CONSTRAINT FK_inbound_receipts_expected_unit
                            REFERENCES inbound.inbound_expected_units(inbound_expected_unit_id),

    inventory_unit_id       INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_inventory
                            REFERENCES inventory.inventory_units(inventory_unit_id),

    received_qty            INT NOT NULL CHECK (received_qty > 0),

    received_by_user_id     INT NOT NULL
                            CONSTRAINT FK_inbound_receipts_user
                            REFERENCES auth.users(id),

    session_id              UNIQUEIDENTIFIER NULL,

    received_at             DATETIME2(3) NOT NULL
                            CONSTRAINT DF_inbound_receipts_received_at
                            DEFAULT SYSUTCDATETIME(),

    is_reversal             BIT NOT NULL DEFAULT(0),
    reversed_receipt_id     INT NULL
                            CONSTRAINT FK_inbound_receipts_reversal
                            REFERENCES inbound.inbound_receipts(receipt_id)
);
GO

CREATE NONCLUSTERED INDEX IX_inbound_receipts_line
ON inbound.inbound_receipts(inbound_line_id)
INCLUDE (received_qty, received_at);
GO

USE PW_Core_DEV;
GO

/* ============================================================
   View: inbound.vw_inbounds_activatable
   ------------------------------------------------------------
   Returns inbound deliveries eligible for activation.

   Criteria:
   - Status = 'EXP' (Expected — not yet activated)
   - Has at least one inbound line
   
   Used by:
   - CLI: ActivateInboundScreen.RenderList()
   - Application: IInboundQueryRepository.GetActivatableInbounds()

   Columns match SqlInboundQueryRepository.GetActivatableInbounds()
   ordinal read: inbound_id(0), inbound_ref(1),
                 expected_arrival_at(2), line_count(3)
   ============================================================ */
GO
