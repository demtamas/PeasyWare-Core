USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   Minimum remaining shelf life
   ------------------------------------------------------------
   Two-tier cascading requirement, resolved at allocation time:
     customer+SKU override -> SKU default -> 0 (the floor: BBE
     must simply still be in the future relative to delivery
     date, which is what "no requirement configured" always
     meant even before this existed).

   Non-batch-managed units (best_before_date IS NULL) are exempt
   entirely - this only ever applies to units that actually carry
   a BBE. Safe to run directly against a live database or as part
   of a full reset - every change here is guarded.
   ============================================================ */

IF COL_LENGTH('inventory.skus', 'minimum_remaining_shelf_life_days') IS NULL
    ALTER TABLE inventory.skus
    ADD minimum_remaining_shelf_life_days INT NULL;

IF OBJECT_ID('inventory.customer_shelf_life_requirements', 'U') IS NULL
BEGIN
    CREATE TABLE inventory.customer_shelf_life_requirements
    (
        customer_party_id                 INT NOT NULL,
        sku_id                             INT NOT NULL,
        minimum_remaining_shelf_life_days INT NOT NULL,

        created_at                        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        created_by                        INT NULL,
        updated_at                        DATETIME2(3) NULL,
        updated_by                        INT NULL,

        CONSTRAINT PK_customer_shelf_life_requirements
            PRIMARY KEY (customer_party_id, sku_id),

        CONSTRAINT FK_customer_shelf_life_customer
            FOREIGN KEY (customer_party_id)
            REFERENCES core.parties(party_id),

        CONSTRAINT FK_customer_shelf_life_sku
            FOREIGN KEY (sku_id)
            REFERENCES inventory.skus(sku_id),

        CONSTRAINT CK_customer_shelf_life_days_nonnegative
            CHECK (minimum_remaining_shelf_life_days >= 0)
    );
END;

GO
PRINT 'Shelf life requirement schema seeded.';
GO
