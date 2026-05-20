USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE TABLE outbound.outbound_order_statuses
(
    status_code VARCHAR(10)  NOT NULL PRIMARY KEY,
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT          NOT NULL DEFAULT (0)
);
GO

INSERT INTO outbound.outbound_order_statuses (status_code, description, is_terminal)
VALUES
    ('NEW',       'New — created, not yet allocated',      0),
    ('ALLOCATED', 'Allocated — stock reserved',            0),
    ('PICKING',   'Picking in progress',                   0),
    ('PICKED',    'Fully picked',                          0),
    ('LOADED',    'Loaded onto vehicle',                   0),
    ('SHIPPED',   'Shipped — departed site',               1),
    ('CNL',       'Cancelled',                             1);
GO

CREATE TABLE outbound.outbound_order_status_transitions
(
    from_status_code VARCHAR(10) NOT NULL,
    to_status_code   VARCHAR(10) NOT NULL,
    requires_authority BIT       NOT NULL DEFAULT (0),

    CONSTRAINT PK_outbound_order_status_transitions
        PRIMARY KEY (from_status_code, to_status_code),

    CONSTRAINT FK_oost_from FOREIGN KEY (from_status_code)
        REFERENCES outbound.outbound_order_statuses(status_code),

    CONSTRAINT FK_oost_to FOREIGN KEY (to_status_code)
        REFERENCES outbound.outbound_order_statuses(status_code)
);
GO

INSERT INTO outbound.outbound_order_status_transitions
    (from_status_code, to_status_code, requires_authority)
VALUES
    ('NEW',       'ALLOCATED', 0),
    ('NEW',       'CNL',       1),
    ('ALLOCATED', 'PICKING',   0),
    ('ALLOCATED', 'NEW',       1),  -- de-allocate
    ('ALLOCATED', 'CNL',       1),
    ('PICKING',   'PICKED',    0),
    ('PICKING',   'ALLOCATED', 1),  -- partial reverse
    ('PICKING',   'CNL',       1),
    ('PICKED',    'LOADED',    0),
    ('PICKED',    'PICKING',   1),  -- un-pick
    ('LOADED',    'SHIPPED',   0),
    ('LOADED',    'PICKED',    1);  -- un-load
GO

PRINT 'outbound_order_statuses + transitions created.';
GO


/********************************************************************************************
    4. outbound_line_statuses + transitions
********************************************************************************************/
CREATE TABLE outbound.outbound_line_statuses
(
    status_code VARCHAR(10)  NOT NULL PRIMARY KEY,
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT          NOT NULL DEFAULT (0)
);
GO

INSERT INTO outbound.outbound_line_statuses (status_code, description, is_terminal)
VALUES
    ('NEW',       'New',                    0),
    ('ALLOCATED', 'Allocated',              0),
    ('PICKING',   'Picking in progress',    0),
    ('PICKED',    'Fully picked',           0),
    ('CNL',       'Cancelled',              1);
GO

CREATE TABLE outbound.outbound_line_status_transitions
(
    from_status_code VARCHAR(10) NOT NULL,
    to_status_code   VARCHAR(10) NOT NULL,
    requires_authority BIT       NOT NULL DEFAULT (0),

    CONSTRAINT PK_outbound_line_status_transitions
        PRIMARY KEY (from_status_code, to_status_code),

    CONSTRAINT FK_olst_from FOREIGN KEY (from_status_code)
        REFERENCES outbound.outbound_line_statuses(status_code),

    CONSTRAINT FK_olst_to FOREIGN KEY (to_status_code)
        REFERENCES outbound.outbound_line_statuses(status_code)
);
GO

INSERT INTO outbound.outbound_line_status_transitions
    (from_status_code, to_status_code, requires_authority)
VALUES
    ('NEW',       'ALLOCATED', 0),
    ('NEW',       'CNL',       1),
    ('ALLOCATED', 'PICKING',   0),
    ('ALLOCATED', 'NEW',       1),
    ('ALLOCATED', 'CNL',       1),
    ('PICKING',   'PICKED',    0),
    ('PICKING',   'ALLOCATED', 1),
    ('PICKING',   'CNL',       1),
    ('PICKED',    'PICKING',   1);
GO

PRINT 'outbound_line_statuses + transitions created.';
GO


/********************************************************************************************
    5. allocation_statuses
********************************************************************************************/
CREATE TABLE outbound.allocation_statuses
(
    status_code VARCHAR(10)  NOT NULL PRIMARY KEY,
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT          NOT NULL DEFAULT (0)
);
GO

INSERT INTO outbound.allocation_statuses (status_code, description, is_terminal)
VALUES
    ('PENDING',   'Pending — unit reserved, task not yet created', 0),
    ('CONFIRMED', 'Confirmed — pick task created',                 0),
    ('PICKED',    'Picked — physical pick confirmed',              1),
    ('CANCELLED', 'Cancelled',                                     1);
GO

PRINT 'allocation_statuses created.';
GO


/********************************************************************************************
    6. shipment_statuses + transitions
********************************************************************************************/
CREATE TABLE outbound.shipment_statuses
(
    status_code VARCHAR(10)  NOT NULL PRIMARY KEY,
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT          NOT NULL DEFAULT (0)
);
GO

INSERT INTO outbound.shipment_statuses (status_code, description, is_terminal)
VALUES
    ('OPEN',     'Open — accepting orders',    0),
    ('LOADING',  'Loading in progress',        0),
    ('DEPARTED', 'Departed site',              1),
    ('CNL',      'Cancelled',                  1);
GO

CREATE TABLE outbound.shipment_status_transitions
(
    from_status_code VARCHAR(10) NOT NULL,
    to_status_code   VARCHAR(10) NOT NULL,
    requires_authority BIT       NOT NULL DEFAULT (0),

    CONSTRAINT PK_shipment_status_transitions
        PRIMARY KEY (from_status_code, to_status_code),

    CONSTRAINT FK_sst_from FOREIGN KEY (from_status_code)
        REFERENCES outbound.shipment_statuses(status_code),

    CONSTRAINT FK_sst_to FOREIGN KEY (to_status_code)
        REFERENCES outbound.shipment_statuses(status_code)
);
GO

INSERT INTO outbound.shipment_status_transitions
    (from_status_code, to_status_code, requires_authority)
VALUES
    ('OPEN',    'LOADING',  0),
    ('OPEN',    'CNL',      1),
    ('LOADING', 'DEPARTED', 0),
    ('LOADING', 'OPEN',     1),   -- un-start loading
    ('LOADING', 'CNL',      1);
GO

PRINT 'shipment_statuses + transitions created.';
GO


/********************************************************************************************
    7. outbound_orders
********************************************************************************************/
CREATE TABLE outbound.outbound_orders
(
    outbound_order_id   INT IDENTITY(1,1) PRIMARY KEY,

    order_ref           NVARCHAR(50)  NOT NULL,

    customer_party_id   INT           NOT NULL,
    haulier_party_id    INT           NULL,
    delivery_address_id INT           NULL,

    -- Linked shipment (set when added to a shipment)
    shipment_id         INT           NULL,

    order_status_code   VARCHAR(10)   NOT NULL DEFAULT ('NEW'),

    -- How the order entered the system
    order_source        VARCHAR(10)   NOT NULL DEFAULT ('MANUAL'),
    -- MANUAL, EDI, API, IMPORT

    required_date       DATE          NULL,
    notes               NVARCHAR(500) NULL,

    created_at          DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT           NULL,
    updated_at          DATETIME2(3)  NULL,
    updated_by          INT           NULL,

    CONSTRAINT UQ_outbound_orders_ref
        UNIQUE (order_ref),

    CONSTRAINT FK_outbound_orders_customer
        FOREIGN KEY (customer_party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT FK_outbound_orders_haulier
        FOREIGN KEY (haulier_party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT FK_outbound_orders_delivery_address
        FOREIGN KEY (delivery_address_id)
        REFERENCES core.party_addresses(address_id),

    CONSTRAINT FK_outbound_orders_status
        FOREIGN KEY (order_status_code)
        REFERENCES outbound.outbound_order_statuses(status_code),

    CONSTRAINT CK_outbound_orders_source
        CHECK (order_source IN ('MANUAL','EDI','API','IMPORT'))
);
GO

PRINT 'outbound.outbound_orders created.';
GO


/********************************************************************************************
    8. outbound_lines
********************************************************************************************/
CREATE TABLE outbound.outbound_lines
(
    outbound_line_id    INT IDENTITY(1,1) PRIMARY KEY,

    outbound_order_id   INT           NOT NULL,
    line_no             INT           NOT NULL,

    sku_id              INT           NOT NULL,
    ordered_qty         INT           NOT NULL CHECK (ordered_qty > 0),
    allocated_qty       INT           NOT NULL DEFAULT (0),
    picked_qty          INT           NOT NULL DEFAULT (0),

    -- Customer-specified batch / BBE (NULL = any available)
    requested_batch     NVARCHAR(100) NULL,
    requested_bbe       DATE          NULL,

    line_status_code    VARCHAR(10)   NOT NULL DEFAULT ('NEW'),

    notes               NVARCHAR(500) NULL,

    created_at          DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by          INT           NULL,
    updated_at          DATETIME2(3)  NULL,
    updated_by          INT           NULL,

    CONSTRAINT UQ_outbound_lines_order_line
        UNIQUE (outbound_order_id, line_no),

    CONSTRAINT FK_outbound_lines_order
        FOREIGN KEY (outbound_order_id)
        REFERENCES outbound.outbound_orders(outbound_order_id),

    CONSTRAINT FK_outbound_lines_sku
        FOREIGN KEY (sku_id)
        REFERENCES inventory.skus(sku_id),

    CONSTRAINT FK_outbound_lines_status
        FOREIGN KEY (line_status_code)
        REFERENCES outbound.outbound_line_statuses(status_code),

    CONSTRAINT CK_outbound_lines_qty_valid
        CHECK (allocated_qty <= ordered_qty AND picked_qty <= allocated_qty)
);
GO

PRINT 'outbound.outbound_lines created.';
GO


/********************************************************************************************
    9. outbound_allocations
    One row per inventory unit allocated to an outbound line.
    Full-pallet allocation — allocated_qty = unit quantity.
    TODO: partial pallet support (case picks, pickfaces) — future
********************************************************************************************/
CREATE TABLE outbound.outbound_allocations
(
    allocation_id       INT IDENTITY(1,1) PRIMARY KEY,

    outbound_line_id    INT           NOT NULL,
    inventory_unit_id   INT           NOT NULL,

    -- Full pallet: equals inventory_units.quantity at time of allocation
    allocated_qty       INT           NOT NULL CHECK (allocated_qty > 0),

    allocation_status   VARCHAR(10)   NOT NULL DEFAULT ('PENDING'),

    allocated_at        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    allocated_by        INT           NULL,

    updated_at          DATETIME2(3)  NULL,
    updated_by          INT           NULL,

    CONSTRAINT FK_allocations_line
        FOREIGN KEY (outbound_line_id)
        REFERENCES outbound.outbound_lines(outbound_line_id),

    CONSTRAINT FK_allocations_unit
        FOREIGN KEY (inventory_unit_id)
        REFERENCES inventory.inventory_units(inventory_unit_id),

    CONSTRAINT FK_allocations_status
        FOREIGN KEY (allocation_status)
        REFERENCES outbound.allocation_statuses(status_code),

    -- One unit can only be on one active allocation at a time
    CONSTRAINT UQ_allocations_active_unit
        UNIQUE (inventory_unit_id)
        -- Note: this is enforced via filtered index below for active allocations only
);
GO

-- Drop the broad UNIQUE — replace with filtered index (active allocations only)
ALTER TABLE outbound.outbound_allocations
DROP CONSTRAINT UQ_allocations_active_unit;
GO

CREATE UNIQUE INDEX UX_allocations_active_unit
ON outbound.outbound_allocations (inventory_unit_id)
WHERE allocation_status <> 'CANCELLED';
GO

PRINT 'outbound.outbound_allocations created.';
GO


/********************************************************************************************
    10. shipments
********************************************************************************************/
CREATE TABLE outbound.shipments
(
    shipment_id          INT IDENTITY(1,1) PRIMARY KEY,

    shipment_ref         NVARCHAR(50)  NOT NULL,

    haulier_party_id     INT           NULL,

    -- Vehicle / trailer reference (licence plate, trailer number)
    vehicle_ref          NVARCHAR(50)  NULL,

    ship_from_address_id INT           NOT NULL,

    planned_departure    DATETIME2(3)  NULL,
    actual_departure     DATETIME2(3)  NULL,

    shipment_status      VARCHAR(10)   NOT NULL DEFAULT ('OPEN'),

    notes                NVARCHAR(500) NULL,

    created_at           DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    created_by           INT           NULL,
    updated_at           DATETIME2(3)  NULL,
    updated_by           INT           NULL,

    CONSTRAINT UQ_shipments_ref
        UNIQUE (shipment_ref),

    CONSTRAINT FK_shipments_haulier
        FOREIGN KEY (haulier_party_id)
        REFERENCES core.parties(party_id),

    CONSTRAINT FK_shipments_address
        FOREIGN KEY (ship_from_address_id)
        REFERENCES core.party_addresses(address_id),

    CONSTRAINT FK_shipments_status
        FOREIGN KEY (shipment_status)
        REFERENCES outbound.shipment_statuses(status_code)
);
GO

-- Add shipment FK to outbound_orders now that shipments table exists
ALTER TABLE outbound.outbound_orders
ADD CONSTRAINT FK_outbound_orders_shipment
    FOREIGN KEY (shipment_id)
    REFERENCES outbound.shipments(shipment_id);
GO

PRINT 'outbound.shipments created.';
GO


/********************************************************************************************
    11. shipment_orders
    Junction table: one shipment → many orders, one order → one shipment.
********************************************************************************************/
CREATE TABLE outbound.shipment_orders
(
    shipment_id         INT          NOT NULL,
    outbound_order_id   INT          NOT NULL,

    added_at            DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    added_by            INT          NULL,

    CONSTRAINT PK_shipment_orders
        PRIMARY KEY (shipment_id, outbound_order_id),

    CONSTRAINT FK_shipment_orders_shipment
        FOREIGN KEY (shipment_id)
        REFERENCES outbound.shipments(shipment_id),

    CONSTRAINT FK_shipment_orders_order
        FOREIGN KEY (outbound_order_id)
        REFERENCES outbound.outbound_orders(outbound_order_id)
);
GO

PRINT 'outbound.shipment_orders created.';
GO


/********************************************************************************************
    12. Indexes
********************************************************************************************/

-- Outbound orders: fast lookup by customer and status
CREATE INDEX IX_outbound_orders_customer_status
ON outbound.outbound_orders (customer_party_id, order_status_code);
GO

-- Outbound orders: fast lookup by shipment
CREATE INDEX IX_outbound_orders_shipment
ON outbound.outbound_orders (shipment_id)
WHERE shipment_id IS NOT NULL;
GO

-- Outbound lines: fast lookup by order
CREATE INDEX IX_outbound_lines_order
ON outbound.outbound_lines (outbound_order_id);
GO

-- Outbound lines: fast lookup by SKU (allocation engine)
CREATE INDEX IX_outbound_lines_sku
ON outbound.outbound_lines (sku_id, line_status_code);
GO

-- Allocations: fast lookup by line
CREATE INDEX IX_allocations_line
ON outbound.outbound_allocations (outbound_line_id);
GO

-- Shipment orders: fast lookup by order
CREATE INDEX IX_shipment_orders_order
ON outbound.shipment_orders (outbound_order_id);
GO

PRINT 'Outbound indexes created.';
GO
GO
