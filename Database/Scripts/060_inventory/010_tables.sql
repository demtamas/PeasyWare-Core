/* ============================================================
   Indexes
   ============================================================ */

-- 1. Unique SSCC + status
CREATE UNIQUE INDEX ux_inventory_units_external_ref
ON inventory.inventory_units (external_ref)
WHERE external_ref IS NOT NULL
  AND stock_state_code <> 'REV'
  AND stock_state_code <> 'SHP'
  AND stock_state_code <> 'MOV';
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_unit
ON inventory.inventory_movements(inventory_unit_id, moved_at DESC);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_reference
ON inventory.inventory_movements(reference_type, reference_id);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_bin
ON inventory.inventory_movements(to_bin_id, moved_at DESC);
GO

CREATE NONCLUSTERED INDEX IX_inventory_movements_state_status
ON inventory.inventory_movements(to_state_code, to_status_code, moved_at DESC);
GO

/* ============================================================
   core.parties
   ------------------------------------------------------------
   Canonical table for all external business entities
   (suppliers, customers, hauliers, owners, etc.).

   One row = one real-world legal entity.
   Roles are assigned separately via core.party_roles.

   This table is intentionally role-agnostic.
   ============================================================ */
GO

CREATE TABLE inventory.skus
(
    sku_id                  INT IDENTITY(1,1) PRIMARY KEY,

    -- External / business identifier (SAP material, item code)
    sku_code                NVARCHAR(50) NOT NULL,

    sku_description         NVARCHAR(255) NOT NULL,

    ean NVARCHAR(20) NULL UNIQUE, -- Barcode for easy scanning.

    uom_code                NVARCHAR(10) NOT NULL,  -- EA, PAL, KG, etc.

    -- Physical characteristics (used later for rules & capacity)
    weight_per_unit         DECIMAL(10,3) NULL,
    standard_hu_quantity INT NULL,
    is_full_hu_required     BIT NOT NULL DEFAULT (0),

    -- Batch / lot control
    is_batch_required       BIT NOT NULL DEFAULT (0), -- If 1, batch number is mandatory at receiving time

    -- Storage intent (THIS is what putaway reads)
    preferred_storage_type_id   INT NOT NULL,
    preferred_storage_section_id INT NULL,

    is_hazardous            BIT NOT NULL DEFAULT (0),
    is_active               BIT NOT NULL DEFAULT (1),

    created_at              DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by              INT NULL,
    updated_at              DATETIME2(3) NULL,
    updated_by              INT NULL,

    CONSTRAINT uq_skus_code
        UNIQUE (sku_code),

    CONSTRAINT fk_skus_storage_type
        FOREIGN KEY (preferred_storage_type_id)
        REFERENCES locations.storage_types(storage_type_id),

    CONSTRAINT fk_skus_storage_section
        FOREIGN KEY (preferred_storage_section_id)
        REFERENCES locations.storage_sections(storage_section_id)
);
GO

/* ============================================================
   inventory.stock_states & statuses
   ------------------------------------------------------------
   Canonical state / status master.
   Defines allowed movements and transitions.
   ============================================================ */
CREATE TABLE inventory.stock_states
(
    state_code        VARCHAR(3)   NOT NULL PRIMARY KEY, -- RCD
    state_code_desc   NVARCHAR(30) NOT NULL,             -- RECEIVED
    is_terminal       BIT NOT NULL DEFAULT 0
);

INSERT INTO inventory.stock_states (state_code, state_code_desc, is_terminal)
VALUES
('EXP', 'EXPECTED', 0),
('RCD', 'RECEIVED', 0),
('PTW', 'PUTAWAY', 0),
('PKD', 'PICKED', 0),
('MOV', 'IN MOVEMENT', 0),
('REV', 'REVERSED', 1),
('SHP', 'SHIPPED', 1);

CREATE TABLE inventory.stock_statuses
(
    status_code       VARCHAR(2)   NOT NULL PRIMARY KEY, -- AV
    status_desc       NVARCHAR(30) NOT NULL              -- AVAILABLE
);

INSERT INTO inventory.stock_statuses (status_code, status_desc)
VALUES
('AV', 'AVAILABLE'),
('QC', 'QC HOLD'),
('BL', 'BLOCKED'),
('DM', 'DAMAGED');

CREATE TABLE inventory.stock_state_transitions
(
    from_state_code    VARCHAR(3) NOT NULL,
    to_state_code      VARCHAR(3) NOT NULL,
    requires_authority BIT NOT NULL DEFAULT 0,
    notes              NVARCHAR(200),

    PRIMARY KEY (from_state_code, to_state_code),

    FOREIGN KEY (from_state_code) REFERENCES inventory.stock_states(state_code),
    FOREIGN KEY (to_state_code)   REFERENCES inventory.stock_states(state_code)
);

INSERT INTO inventory.stock_state_transitions
VALUES
('RCD','PTW',0,'Putaway complete'),
('RCD','REV',1,'Reversed'),
('RCD','MOV',0,'Staging fallback move initiated'),
('PTW','MOV',0,'Bin-to-bin move initiated'),
('MOV','PTW',0,'Move confirmed into destination bin'),
('MOV','RCD',1,'Move cancelled — unit returned to staging'),
('PTW','PKD',0,'Picked'),
('PKD','SHP',0,'Shipped');

CREATE TABLE inventory.stock_operation_rules
(
    state_code     VARCHAR(3) NOT NULL,
    status_code    VARCHAR(2) NOT NULL,

    can_move       BIT NOT NULL DEFAULT 1,
    can_allocate   BIT NOT NULL DEFAULT 1,
    can_ship       BIT NOT NULL DEFAULT 1,
    can_adjust     BIT NOT NULL DEFAULT 1,
    requires_override BIT NOT NULL DEFAULT 0,

    PRIMARY KEY (state_code, status_code),

    FOREIGN KEY (state_code)  REFERENCES inventory.stock_states(state_code),
    FOREIGN KEY (status_code) REFERENCES inventory.stock_statuses(status_code)
);

-- Normal usable stock
INSERT INTO inventory.stock_operation_rules
VALUES
('PTW','AV',1,1,1,1,0),

-- QC Hold
('PTW','QC',1,0,0,1,1),

-- Blocked
('PTW','BL',0,0,0,0,1);
GO

/* ============================================================
   inventory.inventory_units
   ------------------------------------------------------------
   Physical inventory units (pallets, handling units).
   One row = one traceable unit.
   ============================================================ */
/* ============================================================
   inventory.inventory_units
   ------------------------------------------------------------
   Physical inventory units (pallets, handling units).
   One row = one traceable unit.
   ============================================================ */
CREATE TABLE inventory.inventory_units
(
    inventory_unit_id   INT IDENTITY(1,1) PRIMARY KEY,

    sku_id              INT NOT NULL,

    -- External identifier (SSCC, pallet ID, HU)
    external_ref        NVARCHAR(100) NULL,

    batch_number        NVARCHAR(100) NULL,
    best_before_date    DATE NULL,

    quantity            INT NOT NULL,

    -- Lifecycle axis (RCD, PTW, PKD, SHP)
    stock_state_code    VARCHAR(3) NOT NULL,

    -- Restriction axis (AV, QC, BL, DM)
    stock_status_code   VARCHAR(2) NOT NULL,

    created_at          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT NULL,
    updated_at          DATETIME2(3) NULL,
    updated_by          INT NULL,

    CONSTRAINT fk_inventory_units_sku
        FOREIGN KEY (sku_id)
        REFERENCES inventory.skus(sku_id),

    CONSTRAINT fk_inventory_units_state
        FOREIGN KEY (stock_state_code)
        REFERENCES inventory.stock_states(state_code),

    CONSTRAINT fk_inventory_units_status
        FOREIGN KEY (stock_status_code)
        REFERENCES inventory.stock_statuses(status_code)
);
GO

-- 2. Fast lookup by SKU (stock aggregation, joins)
CREATE INDEX ix_inventory_units_sku_id
ON inventory.inventory_units (sku_id);
GO

-- 3. Optimised availability queries (SKU + status filtering)
CREATE INDEX ix_inventory_units_sku_state_status
ON inventory.inventory_units (sku_id, stock_state_code, stock_status_code);
GO

CREATE INDEX IX_inventory_units_state
ON inventory.inventory_units (stock_state_code);
GO

/* ============================================================
   inventory.inventory_placements
   ------------------------------------------------------------
   Current physical placement of inventory units.
   One active placement per inventory unit.
   ============================================================ */
CREATE TABLE inventory.inventory_placements
(
    inventory_unit_id   INT PRIMARY KEY,

    bin_id              INT NOT NULL,

    placed_at           DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    placed_by           INT NULL,

    CONSTRAINT fk_inventory_placements_unit
        FOREIGN KEY (inventory_unit_id)
        REFERENCES inventory.inventory_units(inventory_unit_id),

    CONSTRAINT fk_inventory_placements_bin
        FOREIGN KEY (bin_id)
        REFERENCES locations.bins(bin_id)
);

CREATE INDEX IX_inventory_placements_bin
ON inventory.inventory_placements (bin_id);

/* ============================================================
   inventory.inventory_movements
   ------------------------------------------------------------
   Immutable event log of all stock movements.

   One row = one atomic inventory movement event.
   Never updated. Only inserted.
   ============================================================ */
IF OBJECT_ID('inventory.inventory_movements','U') IS NOT NULL
    DROP TABLE inventory.inventory_movements;
GO

CREATE TABLE inventory.inventory_movements
(
    movement_id            INT IDENTITY(1,1)
                           CONSTRAINT PK_inventory_movements
                           PRIMARY KEY,

    /* --------------------------------------------------------
       What moved
       -------------------------------------------------------- */

    inventory_unit_id      INT NOT NULL
                           CONSTRAINT FK_inventory_movements_unit
                           REFERENCES inventory.inventory_units(inventory_unit_id),

    sku_id                 INT NOT NULL
                           CONSTRAINT FK_inventory_movements_sku
                           REFERENCES inventory.skus(sku_id),

    moved_qty              INT NOT NULL
                           CHECK (moved_qty > 0),

    /* --------------------------------------------------------
       Location transition
       -------------------------------------------------------- */

    from_bin_id            INT NULL
                           CONSTRAINT FK_inventory_movements_from_bin
                           REFERENCES locations.bins(bin_id),

    to_bin_id              INT NULL
                           CONSTRAINT FK_inventory_movements_to_bin
                           REFERENCES locations.bins(bin_id),

    /* --------------------------------------------------------
       Lifecycle transition (NEW)
       -------------------------------------------------------- */

    from_state_code        VARCHAR(3) NULL
                           CONSTRAINT FK_inventory_movements_from_state
                           REFERENCES inventory.stock_states(state_code),

    to_state_code          VARCHAR(3) NULL
                           CONSTRAINT FK_inventory_movements_to_state
                           REFERENCES inventory.stock_states(state_code),

    /* --------------------------------------------------------
       Restriction transition (NEW)
       -------------------------------------------------------- */

    from_status_code       VARCHAR(2) NULL
                           CONSTRAINT FK_inventory_movements_from_status
                           REFERENCES inventory.stock_statuses(status_code),

    to_status_code         VARCHAR(2) NULL
                           CONSTRAINT FK_inventory_movements_to_status
                           REFERENCES inventory.stock_statuses(status_code),

    /* --------------------------------------------------------
       Business context
       -------------------------------------------------------- */

    movement_type          NVARCHAR(30) NOT NULL,
    -- RECEIVE
    -- PUTAWAY
    -- BIN_MOVE
    -- ALLOCATE
    -- DEALLOCATE
    -- PICK
    -- LOAD
    -- SHIP
    -- ADJUSTMENT
    -- STATUS_CHANGE
    -- STATE_CHANGE
    -- REVERSAL

    reference_type         NVARCHAR(30) NULL,
    -- INBOUND
    -- OUTBOUND
    -- ADJUSTMENT
    -- MANUAL

    reference_id           INT NULL,

    /* --------------------------------------------------------
       Operational metadata
       -------------------------------------------------------- */

    moved_at               DATETIME2(3) NOT NULL
                           CONSTRAINT DF_inventory_movements_moved_at
                           DEFAULT SYSUTCDATETIME(),

    moved_by_user_id       INT NOT NULL
                           CONSTRAINT FK_inventory_movements_user
                           REFERENCES auth.users(id),

    session_id             UNIQUEIDENTIFIER NULL,

    /* --------------------------------------------------------
       Reversal control
       -------------------------------------------------------- */

    is_reversal            BIT NOT NULL DEFAULT(0),

    reversed_movement_id   INT NULL
                           CONSTRAINT FK_inventory_movements_reversal
                           REFERENCES inventory.inventory_movements(movement_id)
);
GO
