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

INSERT INTO outbound.outbound_line_statuses (status_code, description, is_terminal)
VALUES
    ('NEW',       'New',                    0),
    ('ALLOCATED', 'Allocated',              0),
    ('PICKING',   'Picking in progress',    0),
    ('PICKED',    'Fully picked',           0),
    ('CNL',       'Cancelled',              1);
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

INSERT INTO outbound.allocation_statuses (status_code, description, is_terminal)
VALUES
    ('PENDING',   'Pending — unit reserved, task not yet created', 0),
    ('CONFIRMED', 'Confirmed — pick task created',                 0),
    ('PICKED',    'Picked — physical pick confirmed',              1),
    ('CANCELLED', 'Cancelled',                                     1);
GO

PRINT 'allocation_statuses created.';
GO

INSERT INTO outbound.shipment_statuses (status_code, description, is_terminal)
VALUES
    ('OPEN',     'Open — accepting orders',    0),
    ('LOADING',  'Loading in progress',        0),
    ('DEPARTED', 'Departed site',              1),
    ('CNL',      'Cancelled',                  1);
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

PRINT 'outbound.outbound_orders created.';
GO

PRINT 'outbound.outbound_lines created.';
GO

CREATE UNIQUE INDEX UX_allocations_active_unit
ON outbound.outbound_allocations (inventory_unit_id)
WHERE allocation_status <> 'CANCELLED';
GO

PRINT 'outbound.outbound_allocations created.';
GO

PRINT 'outbound.shipments created.';
GO

PRINT 'outbound.shipment_orders created.';
GO

PRINT 'Outbound indexes created.';
GO

/********************************************************************************************
    13. Error codes
********************************************************************************************/
INSERT INTO operations.error_messages
    (error_code, module_code, severity, message_template, tech_messege)
SELECT v.error_code, v.module_code, v.severity, v.message_template, v.tech_messege
FROM (VALUES

    -- Order
    (N'ERRORD01', N'ORD', N'ERROR',
        N'Order not found.',
        N'Order: outbound_order_id not found'),

    (N'ERRORD02', N'ORD', N'ERROR',
        N'Order is not in a valid state for this operation.',
        N'Order: invalid status transition'),

    (N'ERRORD03', N'ORD', N'ERROR',
        N'Order reference already exists.',
        N'Order.Create: duplicate order_ref'),

    (N'ERRORD04', N'ORD', N'ERROR',
        N'Order has no lines and cannot be processed.',
        N'Order: no active lines'),

    (N'SUCORD01', N'ORD', N'INFO',
        N'Order created successfully.',
        N'Order.Create: success'),

    (N'SUCORD02', N'ORD', N'INFO',
        N'Order allocated successfully.',
        N'Order.Allocate: success'),

    (N'SUCORD03', N'ORD', N'INFO',
        N'Order shipped successfully.',
        N'Order.Ship: success'),

    -- Allocation
    (N'ERRALLOC01', N'ALLOC', N'ERROR',
        N'Insufficient stock available to fulfil this order line.',
        N'Allocate: not enough PUTAWAY+AVAILABLE units for SKU'),

    (N'ERRALLOC02', N'ALLOC', N'ERROR',
        N'Requested batch or best-before date not available.',
        N'Allocate: no units matching requested_batch / requested_bbe'),

    (N'ERRALLOC03', N'ALLOC', N'ERROR',
        N'Unit is already allocated to another order.',
        N'Allocate: inventory_unit already has active allocation'),

    (N'SUCALLOC01', N'ALLOC', N'INFO',
        N'Stock allocated successfully.',
        N'Allocate: allocation rows created'),

    -- Pick
    (N'ERRPICK01', N'PICK', N'ERROR',
        N'Allocation not found or already picked.',
        N'Pick: allocation_id not found or status terminal'),

    (N'ERRPICK02', N'PICK', N'ERROR',
        N'Wrong pallet scanned. Expected a different SSCC.',
        N'Pick.Confirm: scanned SSCC does not match allocated unit'),

    (N'ERRPICK03', N'PICK', N'ERROR',
        N'Unit is not in the expected location.',
        N'Pick.Confirm: unit placement bin does not match task source bin'),

    (N'SUCPICK01', N'PICK', N'INFO',
        N'Pick confirmed successfully.',
        N'Pick.Confirm: unit transitioned to PKD'),

    -- Shipment
    (N'ERRSHIP01', N'SHIP', N'ERROR',
        N'Shipment not found.',
        N'Shipment: shipment_id not found'),

    (N'ERRSHIP02', N'SHIP', N'ERROR',
        N'Shipment is not in a valid state for this operation.',
        N'Shipment: invalid status transition'),

    (N'ERRSHIP03', N'SHIP', N'ERROR',
        N'Shipment reference already exists.',
        N'Shipment.Create: duplicate shipment_ref'),

    (N'ERRSHIP04', N'SHIP', N'ERROR',
        N'Not all orders on this shipment are fully picked.',
        N'Shipment.Ship: one or more orders not in PICKED or LOADED status'),

    (N'SUCSHIP01', N'SHIP', N'INFO',
        N'Shipment created successfully.',
        N'Shipment.Create: success'),

    (N'SUCSHIP02', N'SHIP', N'INFO',
        N'Shipment departed. All units shipped.',
        N'Shipment.Ship: all units transitioned to SHP')

) AS v (error_code, module_code, severity, message_template, tech_messege)
WHERE NOT EXISTS (
    SELECT 1 FROM operations.error_messages e
    WHERE e.error_code = v.error_code
);
GO

PRINT 'Outbound error codes inserted.';
GO

GO


/********************************************************************************************
    OUTBOUND STORED PROCEDURES
    All 7 outbound SPs. CREATE OR ALTER — safe to re-run after DB reset.
********************************************************************************************/

/********************************************************************************************
    WIP PATCH — Pick flow improvements
    Date: 2026-04-18

    1. usp_pick_create: add @destination_bin_code parameter
       Operator can specify which staging bay to pick into.
       If NULL, falls back to first active staging bin (existing behaviour).
********************************************************************************************/
GO

CREATE TABLE outbound.outbound_order_statuses
(
    status_code VARCHAR(10)  NOT NULL PRIMARY KEY,
    description NVARCHAR(50) NOT NULL,
    is_terminal BIT          NOT NULL DEFAULT (0)
);
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

-- Add shipment FK to outbound_orders now that shipments table exists
ALTER TABLE outbound.outbound_orders
ADD CONSTRAINT FK_outbound_orders_shipment
    FOREIGN KEY (shipment_id)
    REFERENCES outbound.shipments(shipment_id);
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

-- Drop the broad UNIQUE — replace with filtered index (active allocations only)
ALTER TABLE outbound.outbound_allocations
DROP CONSTRAINT UQ_allocations_active_unit;
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
