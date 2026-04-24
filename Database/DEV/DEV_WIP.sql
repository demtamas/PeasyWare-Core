USE PW_Core_DEV;
GO

/********************************************************************************************
    WIP PATCH — API creation SPs
    Date: 2026-04-24

    New stored procedures for API data entry:
      1. inventory.usp_create_sku
      2. inbound.usp_create_inbound
      3. inbound.usp_create_inbound_line
      4. inbound.usp_create_expected_unit
      5. outbound.usp_create_order          (party-code based)
      6. outbound.usp_create_shipment       (party-code based)
      7. outbound.usp_add_order_to_shipment (ref-based overload)

    Error codes added:
      ERRSKU01 — SKU not found
      ERRSKU02 — SKU already exists
      SUCSKU01 — SKU created
      ERRINB02 — Inbound ref already exists
      SUCINB02 — Inbound created via API
      SUCINBL02 — Inbound line created via API
      SUCINBU01 — Expected unit created
      ERRINBU01 — SSCC already exists on this inbound
      ERRORD02  — Order ref already exists
      SUCORD01  — Order created
      ERRSHIP02 — Shipment ref already exists
      SUCSHIP01 — Shipment created
      ERRSHIP03 — Shipment not found (add order)
      ERRORD03  — Order not found (add to shipment)
      SUCSHIP03 — Order added to shipment
********************************************************************************************/

-- ── Error messages ───────────────────────────────────────────────────────

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU01', N'SKU', N'ERROR', N'SKU not found.', N'inventory.usp_create_sku: sku_code not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSKU02', N'SKU', N'ERROR', N'A SKU with this code already exists.', N'inventory.usp_create_sku: duplicate sku_code'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSKU02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSKU01', N'SKU', N'SUCCESS', N'SKU created successfully.', N'inventory.usp_create_sku: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSKU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINB02', N'INB', N'ERROR', N'An inbound delivery with this reference already exists.', N'inbound.usp_create_inbound: duplicate inbound_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINB02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINB02', N'INB', N'SUCCESS', N'Inbound delivery created successfully.', N'inbound.usp_create_inbound: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINB02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINBL02', N'INB', N'SUCCESS', N'Inbound line created successfully.', N'inbound.usp_create_inbound_line: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINBL02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCINBU01', N'INB', N'SUCCESS', N'Expected unit created successfully.', N'inbound.usp_create_expected_unit: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCINBU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRINBU01', N'INB', N'ERROR', N'This SSCC is already registered on this inbound delivery.', N'inbound.usp_create_expected_unit: duplicate sscc on inbound'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRINBU01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD02', N'ORD', N'ERROR', N'An order with this reference already exists.', N'outbound.usp_create_order: duplicate order_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCORD01', N'ORD', N'SUCCESS', N'Order created successfully.', N'outbound.usp_create_order: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCORD01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP02', N'SHIP', N'ERROR', N'A shipment with this reference already exists.', N'outbound.usp_create_shipment: duplicate shipment_ref'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP02');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP01', N'SHIP', N'SUCCESS', N'Shipment created successfully.', N'outbound.usp_create_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP01');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRSHIP03', N'SHIP', N'ERROR', N'Shipment not found.', N'outbound.usp_add_order_to_shipment: shipment_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRSHIP03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'ERRORD03', N'ORD', N'ERROR', N'Order not found.', N'outbound.usp_add_order_to_shipment: order_ref not found'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRORD03');

INSERT INTO operations.error_messages (error_code, module_code, severity, message_template, tech_messege)
SELECT N'SUCSHIP03', N'SHIP', N'SUCCESS', N'Order added to shipment successfully.', N'outbound.usp_add_order_to_shipment: success'
WHERE NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'SUCSHIP03');

GO
PRINT 'API error messages inserted.';
GO

-- ── 1. inventory.usp_create_sku ─────────────────────────────────────────

CREATE OR ALTER PROCEDURE inventory.usp_create_sku
(
    @sku_code             NVARCHAR(50),
    @sku_description      NVARCHAR(200),
    @ean                  NVARCHAR(50)  = NULL,
    @uom_code             NVARCHAR(20)  = N'Each',
    @weight_per_unit      DECIMAL(10,3) = NULL,
    @standard_hu_quantity INT           = 0,
    @is_hazardous         BIT           = 0,
    @user_id              INT           = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM inventory.skus WHERE sku_code = @sku_code)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSKU02' AS result_code, NULL AS sku_id;
            ROLLBACK;
            RETURN;
        END

        -- Resolve default storage type (RACK preferred, fallback to first available)
        DECLARE @default_storage_type_id INT =
            ISNULL(
                (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE storage_type_code = 'RACK' AND is_active = 1),
                (SELECT TOP 1 storage_type_id FROM locations.storage_types WHERE is_active = 1 ORDER BY storage_type_id)
            );

        INSERT INTO inventory.skus
            (sku_code, sku_description, ean, uom_code, weight_per_unit,
             standard_hu_quantity, is_hazardous, is_active,
             preferred_storage_type_id, created_at, created_by)
        VALUES
            (@sku_code, @sku_description, @ean, @uom_code, @weight_per_unit,
             @standard_hu_quantity, @is_hazardous, 1,
             @default_storage_type_id, SYSUTCDATETIME(), @user_id);

        DECLARE @sku_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSKU01' AS result_code, @sku_id AS sku_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSKU99' AS result_code, NULL AS sku_id;
    END CATCH
END;
GO
PRINT 'inventory.usp_create_sku created.';
GO

-- ── 2. inbound.usp_create_inbound ───────────────────────────────────────

CREATE OR ALTER PROCEDURE inbound.usp_create_inbound
(
    @inbound_ref         NVARCHAR(50),
    @supplier_party_code NVARCHAR(50),
    @haulier_party_code  NVARCHAR(50)     = NULL,
    @expected_arrival_at DATETIME2(3)     = NULL,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM inbound.inbound_deliveries WHERE inbound_ref = @inbound_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB02' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @supplier_id INT = (
            SELECT party_id FROM core.parties WHERE party_code = @supplier_party_code
        );

        IF @supplier_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @haulier_id INT = NULL;
        IF @haulier_party_code IS NOT NULL
            SET @haulier_id = (
                SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code
            );

        DECLARE @ship_to_id INT = (
            SELECT TOP 1 pa.address_id
            FROM core.party_addresses pa
            JOIN core.parties p ON pa.party_id = p.party_id
            JOIN core.party_roles pr ON pr.party_id = p.party_id
            WHERE pr.role_code = 'WAREHOUSE'
              AND pa.is_primary = 1
        );

        INSERT INTO inbound.inbound_deliveries
            (inbound_ref, supplier_party_id, owner_party_id, haulier_party_id,
             ship_to_address_id, expected_arrival_at, created_at, created_by)
        VALUES
            (@inbound_ref, @supplier_id, @supplier_id, @haulier_id,
             @ship_to_id, @expected_arrival_at, SYSUTCDATETIME(), @user_id);

        DECLARE @inbound_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINB02' AS result_code, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code, NULL AS inbound_id;
    END CATCH
END;
GO
PRINT 'inbound.usp_create_inbound created.';
GO

-- ── 3. inbound.usp_create_inbound_line ──────────────────────────────────

CREATE OR ALTER PROCEDURE inbound.usp_create_inbound_line
(
    @inbound_ref          NVARCHAR(50),
    @sku_code             NVARCHAR(50),
    @expected_qty         INT,
    @batch_number         NVARCHAR(100)    = NULL,
    @best_before_date     DATE             = NULL,
    @arrival_stock_status NVARCHAR(2)      = N'AV',
    @user_id              INT              = NULL,
    @session_id           UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @inbound_id INT = (
            SELECT inbound_id FROM inbound.inbound_deliveries WHERE inbound_ref = @inbound_ref
        );

        IF @inbound_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @sku_id INT = (
            SELECT sku_id FROM inventory.skus WHERE sku_code = @sku_code AND is_active = 1
        );

        IF @sku_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSKU01' AS result_code,
                   NULL AS inbound_line_id, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @line_no INT = ISNULL(
            (SELECT MAX(line_no) FROM inbound.inbound_lines WHERE inbound_id = @inbound_id), 0
        ) + 10;

        INSERT INTO inbound.inbound_lines
            (inbound_id, line_no, sku_id, expected_qty, received_qty,
             batch_number, best_before_date, arrival_stock_status_code,
             created_at, created_by)
        VALUES
            (@inbound_id, @line_no, @sku_id, @expected_qty, 0,
             @batch_number, @best_before_date, @arrival_stock_status,
             SYSUTCDATETIME(), @user_id);

        DECLARE @inbound_line_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINBL02' AS result_code,
               @inbound_line_id AS inbound_line_id, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code,
               NULL AS inbound_line_id, NULL AS inbound_id;
    END CATCH
END;
GO
PRINT 'inbound.usp_create_inbound_line created.';
GO

-- ── 4. inbound.usp_create_expected_unit ─────────────────────────────────
-- Adds an SSCC to the most recently added line on this inbound.
-- If the inbound has multiple lines, the caller must extend this
-- or add a @sku_code parameter to target a specific line.

CREATE OR ALTER PROCEDURE inbound.usp_create_expected_unit
(
    @inbound_ref     NVARCHAR(50),
    @sscc            NVARCHAR(18),
    @quantity        INT,
    @batch_number    NVARCHAR(100)    = NULL,
    @best_before_date DATE            = NULL,
    @user_id         INT              = NULL,
    @session_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Resolve to the most recent line on this inbound
        DECLARE @inbound_line_id INT = (
            SELECT TOP 1 l.inbound_line_id
            FROM inbound.inbound_lines l
            JOIN inbound.inbound_deliveries d ON d.inbound_id = l.inbound_id
            WHERE d.inbound_ref = @inbound_ref
            ORDER BY l.line_no DESC
        );

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code,
                   NULL AS inbound_expected_unit_id;
            ROLLBACK;
            RETURN;
        END

        -- Duplicate SSCC check within this inbound
        IF EXISTS (
            SELECT 1
            FROM inbound.inbound_expected_units eu
            JOIN inbound.inbound_lines l ON l.inbound_line_id = eu.inbound_line_id
            JOIN inbound.inbound_deliveries d ON d.inbound_id = l.inbound_id
            WHERE d.inbound_ref = @inbound_ref
              AND eu.expected_external_ref = @sscc
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBU01' AS result_code,
                   NULL AS inbound_expected_unit_id;
            ROLLBACK;
            RETURN;
        END

        INSERT INTO inbound.inbound_expected_units
            (inbound_line_id, expected_external_ref, expected_quantity,
             batch_number, best_before_date, created_at, created_by)
        VALUES
            (@inbound_line_id, @sscc, @quantity,
             @batch_number, @best_before_date, SYSUTCDATETIME(), @user_id);

        DECLARE @unit_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINBU01' AS result_code,
               @unit_id AS inbound_expected_unit_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code,
               NULL AS inbound_expected_unit_id;
    END CATCH
END;
GO
PRINT 'inbound.usp_create_expected_unit created.';
GO

-- ── 5. outbound.usp_create_order (party-code based) ─────────────────────

CREATE OR ALTER PROCEDURE outbound.usp_create_order
(
    @order_ref           NVARCHAR(50),
    @customer_party_code NVARCHAR(50),
    @haulier_party_code  NVARCHAR(50)     = NULL,
    @required_date       DATE             = NULL,
    @notes               NVARCHAR(500)    = NULL,
    @lines_json          NVARCHAR(MAX)    = NULL,
    @user_id             INT              = NULL,
    @session_id          UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM outbound.outbound_orders WHERE order_ref = @order_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD02' AS result_code, NULL AS outbound_order_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @customer_id INT = (
            SELECT party_id FROM core.parties WHERE party_code = @customer_party_code
        );

        IF @customer_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS outbound_order_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @haulier_id INT = NULL;
        IF @haulier_party_code IS NOT NULL
            SET @haulier_id = (SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code);

        INSERT INTO outbound.outbound_orders
            (order_ref, customer_party_id, haulier_party_id, required_date,
             order_status_code, order_source, notes, created_at, created_by)
        VALUES
            (@order_ref, @customer_id, @haulier_id, @required_date,
             'NEW', 'API', @notes, SYSUTCDATETIME(), @user_id);

        DECLARE @order_id INT = SCOPE_IDENTITY();

        -- Insert lines from JSON
        IF @lines_json IS NOT NULL
        BEGIN
            INSERT INTO outbound.outbound_lines
                (outbound_order_id, line_no, sku_id, ordered_qty,
                 requested_batch, requested_bbe, notes, created_at, created_by)
            SELECT
                @order_id,
                l.line_no,
                s.sku_id,
                l.ordered_qty,
                l.requested_batch,
                TRY_CAST(l.requested_bbe AS DATE),
                l.notes,
                SYSUTCDATETIME(),
                @user_id
            FROM OPENJSON(@lines_json) WITH (
                line_no        INT            '$.line_no',
                sku_code       NVARCHAR(50)   '$.sku_code',
                ordered_qty    INT            '$.ordered_qty',
                requested_batch NVARCHAR(100) '$.requested_batch',
                requested_bbe  NVARCHAR(20)   '$.requested_bbe',
                notes          NVARCHAR(500)  '$.notes'
            ) l
            JOIN inventory.skus s ON s.sku_code = l.sku_code;
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCORD01' AS result_code, @order_id AS outbound_order_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRORD99' AS result_code, NULL AS outbound_order_id;
    END CATCH
END;
GO
PRINT 'outbound.usp_create_order created.';
GO

-- ── 6. outbound.usp_create_shipment (party-code based) ──────────────────

CREATE OR ALTER PROCEDURE outbound.usp_create_shipment
(
    @shipment_ref       NVARCHAR(50),
    @haulier_party_code NVARCHAR(50),
    @vehicle_ref        NVARCHAR(50)     = NULL,
    @planned_departure  DATETIME2(3)     = NULL,
    @notes              NVARCHAR(500)    = NULL,
    @user_id            INT              = NULL,
    @session_id         UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF EXISTS (SELECT 1 FROM outbound.shipments WHERE shipment_ref = @shipment_ref)
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP02' AS result_code, NULL AS shipment_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @haulier_id INT = (
            SELECT party_id FROM core.parties WHERE party_code = @haulier_party_code
        );

        IF @haulier_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRPARTY01' AS result_code, NULL AS shipment_id;
            ROLLBACK;
            RETURN;
        END

        DECLARE @ship_from_id INT = (
            SELECT TOP 1 pa.address_id
            FROM core.party_addresses pa
            JOIN core.parties p ON pa.party_id = p.party_id
            JOIN core.party_roles pr ON pr.party_id = p.party_id
            WHERE pr.role_code = 'WAREHOUSE'
              AND pa.is_primary = 1
        );

        INSERT INTO outbound.shipments
            (shipment_ref, haulier_party_id, vehicle_ref,
             ship_from_address_id, planned_departure,
             shipment_status, notes, created_at, created_by)
        VALUES
            (@shipment_ref, @haulier_id, @vehicle_ref,
             @ship_from_id, @planned_departure,
             'OPEN', @notes, SYSUTCDATETIME(), @user_id);

        DECLARE @shipment_id INT = SCOPE_IDENTITY();

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP01' AS result_code, @shipment_id AS shipment_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP99' AS result_code, NULL AS shipment_id;
    END CATCH
END;
GO
PRINT 'outbound.usp_create_shipment created.';
GO

-- ── 7. outbound.usp_add_order_to_shipment (ref-based overload) ──────────

CREATE OR ALTER PROCEDURE outbound.usp_add_order_to_shipment
(
    @shipment_ref NVARCHAR(50),
    @order_ref    NVARCHAR(50),
    @user_id      INT              = NULL,
    @session_id   UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @shipment_id INT = (
            SELECT shipment_id FROM outbound.shipments WHERE shipment_ref = @shipment_ref
        );

        IF @shipment_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRSHIP03' AS result_code;
            ROLLBACK;
            RETURN;
        END

        DECLARE @order_id INT = (
            SELECT outbound_order_id FROM outbound.outbound_orders WHERE order_ref = @order_ref
        );

        IF @order_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRORD03' AS result_code;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS (
            SELECT 1 FROM outbound.shipment_orders
            WHERE shipment_id = @shipment_id AND outbound_order_id = @order_id
        )
        BEGIN
            INSERT INTO outbound.shipment_orders (shipment_id, outbound_order_id, added_at, added_by)
            VALUES (@shipment_id, @order_id, SYSUTCDATETIME(), @user_id);
        END

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCSHIP03' AS result_code;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRSHIP99' AS result_code;
    END CATCH
END;
GO
PRINT 'outbound.usp_add_order_to_shipment created.';
GO

PRINT '------------------------------------------------------------';
PRINT 'API SPs patch complete.';
PRINT '------------------------------------------------------------';
GO
