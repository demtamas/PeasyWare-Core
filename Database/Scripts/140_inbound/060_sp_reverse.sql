IF OBJECT_ID('audit.fn_map_user_result') IS NOT NULL
    DROP FUNCTION audit.fn_map_user_result;
GO

/* ============================================================
   10. CREATE USER (provisioning)
   ============================================================*/
GO

CREATE OR ALTER PROCEDURE inbound.usp_reverse_inbound_receipt
(
    @receipt_id      INT,
    @reason_code     NVARCHAR(50) = NULL,
    @reason_text     NVARCHAR(400) = NULL,
    @user_id         INT = NULL,
    @session_id      UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
    EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

    DECLARE
        @inbound_id               INT,
        @inbound_line_id          INT,
        @inbound_expected_unit_id INT,
        @inventory_unit_id        INT,
        @received_qty             INT,
        @reversal_receipt_id      INT,
        @header_reopened          BIT = 0,
        @old_header_status        VARCHAR(3),
        @new_header_status        VARCHAR(3);

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @inbound_line_id          = r.inbound_line_id,
            @inbound_expected_unit_id = r.inbound_expected_unit_id,
            @inventory_unit_id        = r.inventory_unit_id,
            @received_qty             = r.received_qty
        FROM inbound.inbound_receipts r WITH (UPDLOCK, HOLDLOCK)
        WHERE r.receipt_id = @receipt_id
          AND r.is_reversal = 0;

        IF @inbound_line_id IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBREV01' AS result_code,
                   NULL AS inbound_id, NULL AS inbound_line_id,
                   NULL AS receipt_id, NULL AS reversal_receipt_id,
                   NULL AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
            ROLLBACK;
            RETURN;
        END

        IF EXISTS
        (
            SELECT 1
            FROM inbound.inbound_receipts
            WHERE receipt_id = @receipt_id
              AND reversed_receipt_id IS NOT NULL
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBREV02' AS result_code,
                   NULL AS inbound_id, NULL AS inbound_line_id,
                   @receipt_id AS receipt_id, NULL AS reversal_receipt_id,
                   NULL AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
            ROLLBACK;
            RETURN;
        END

        SELECT @inbound_id = inbound_id
        FROM inbound.inbound_lines
        WHERE inbound_line_id = @inbound_line_id;

        SELECT @old_header_status = inbound_status_code
        FROM inbound.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        DECLARE
            @sku_id               INT,
            @from_bin_id          INT,
            @unit_status_code     VARCHAR(2),
            @original_movement_id INT;

        SELECT
            @sku_id           = iu.sku_id,
            @unit_status_code = iu.stock_status_code,
            @from_bin_id      = ip.bin_id
        FROM inventory.inventory_units iu
        LEFT JOIN inventory.inventory_placements ip
            ON ip.inventory_unit_id = iu.inventory_unit_id
        WHERE iu.inventory_unit_id = @inventory_unit_id;

        SELECT @original_movement_id = movement_id
        FROM inventory.inventory_movements
        WHERE inventory_unit_id = @inventory_unit_id
          AND movement_type     = 'INBOUND'
          AND is_reversal       = 0;

        UPDATE inventory.inventory_units
        SET stock_state_code = 'REV',
            updated_at       = SYSUTCDATETIME(),
            updated_by       = @user_id
        WHERE inventory_unit_id = @inventory_unit_id;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBREV03' AS result_code,
                   @inbound_id AS inbound_id, @inbound_line_id AS inbound_line_id,
                   @receipt_id AS receipt_id, NULL AS reversal_receipt_id,
                   @inventory_unit_id AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
            ROLLBACK;
            RETURN;
        END

        DELETE FROM inventory.inventory_placements
        WHERE inventory_unit_id = @inventory_unit_id;

        INSERT INTO inventory.inventory_movements
        (
            inventory_unit_id, sku_id, moved_qty,
            from_bin_id, to_bin_id,
            from_state_code, to_state_code,
            from_status_code, to_status_code,
            movement_type, reference_type, reference_id,
            moved_at, moved_by_user_id, session_id,
            is_reversal, reversed_movement_id
        )
        VALUES
        (
            @inventory_unit_id, @sku_id, @received_qty,
            @from_bin_id, NULL,
            'RCD', 'REV',
            @unit_status_code, @unit_status_code,
            'REVERSAL', 'INBOUND', @receipt_id,
            SYSUTCDATETIME(), @user_id, @session_id,
            1, @original_movement_id
        );

        IF @inbound_expected_unit_id IS NOT NULL
        BEGIN
            UPDATE inbound.inbound_expected_units
            SET received_inventory_unit_id = NULL,
                expected_unit_state_code   = 'EXP',
                claimed_session_id         = NULL,
                claimed_by_user_id         = NULL,
                claimed_at                 = NULL,
                claim_expires_at           = NULL,
                claim_token                = NULL,
                updated_at                 = SYSUTCDATETIME(),
                updated_by                 = @user_id
            WHERE inbound_expected_unit_id = @inbound_expected_unit_id;
        END

        INSERT INTO inbound.inbound_receipts
        (
            inbound_line_id, inbound_expected_unit_id, inventory_unit_id,
            received_qty, received_by_user_id, session_id,
            received_at, is_reversal, reversed_receipt_id
        )
        VALUES
        (
            @inbound_line_id, @inbound_expected_unit_id, @inventory_unit_id,
            @received_qty, @user_id, @session_id,
            SYSUTCDATETIME(), 1, @receipt_id
        );

        SET @reversal_receipt_id = SCOPE_IDENTITY();

        UPDATE inbound.inbound_receipts
        SET reversed_receipt_id = @reversal_receipt_id
        WHERE receipt_id = @receipt_id;

        UPDATE l
        SET
            received_qty =
            (
                SELECT ISNULL(SUM(
                    CASE
                        WHEN r.is_reversal = 0 THEN r.received_qty
                        ELSE -r.received_qty
                    END), 0)
                FROM inbound.inbound_receipts r
                WHERE r.inbound_line_id = l.inbound_line_id
            ),
            line_state_code =
            CASE
                WHEN (
                    SELECT ISNULL(SUM(
                        CASE
                            WHEN r.is_reversal = 0 THEN r.received_qty
                            ELSE -r.received_qty
                        END), 0)
                    FROM inbound.inbound_receipts r
                    WHERE r.inbound_line_id = l.inbound_line_id
                ) = 0 THEN 'EXP'
                WHEN (
                    SELECT ISNULL(SUM(
                        CASE
                            WHEN r.is_reversal = 0 THEN r.received_qty
                            ELSE -r.received_qty
                        END), 0)
                    FROM inbound.inbound_receipts r
                    WHERE r.inbound_line_id = l.inbound_line_id
                ) < l.expected_qty THEN 'PRC'
                ELSE 'RCV'
            END,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        FROM inbound.inbound_lines l
        WHERE l.inbound_line_id = @inbound_line_id;

        SET @new_header_status = 'ACT';

        IF EXISTS
        (
            SELECT 1 FROM inbound.inbound_lines
            WHERE inbound_id = @inbound_id AND line_state_code IN ('PRC','RCV')
        )
            SET @new_header_status = 'RCV';

        IF NOT EXISTS
        (
            SELECT 1 FROM inbound.inbound_lines
            WHERE inbound_id = @inbound_id AND line_state_code NOT IN ('RCV','CNL')
        )
            SET @new_header_status = 'CLS';

        UPDATE inbound.inbound_deliveries
        SET inbound_status_code = @new_header_status,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        IF @old_header_status = 'CLS' AND @new_header_status <> 'CLS'
            SET @header_reopened = 1;

        COMMIT;

        SELECT
            CAST(1 AS BIT)        AS success,
            N'SUCINBREV01'        AS result_code,
            @inbound_id           AS inbound_id,
            @inbound_line_id      AS inbound_line_id,
            @receipt_id           AS receipt_id,
            @reversal_receipt_id  AS reversal_receipt_id,
            @inventory_unit_id    AS inventory_unit_id,
            @header_reopened      AS header_reopened;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT
            CAST(0 AS BIT)  AS success, N'ERRINBREV99'  AS result_code,
            NULL AS inbound_id, NULL AS inbound_line_id,
            @receipt_id AS receipt_id, NULL AS reversal_receipt_id,
            NULL AS inventory_unit_id, CAST(0 AS BIT) AS header_reopened;
    END CATCH
END;
GO

/* ========================================================
   EVENT RESULT CODES (IDEMPOTENT INSERT)
======================================================== */

/* ========================================================
   EVENT CATALOG TABLE
======================================================== */

IF OBJECT_ID('audit.event_catalog') IS NULL
BEGIN
    CREATE TABLE audit.event_catalog
    (
        event_name NVARCHAR(200) PRIMARY KEY,
        description NVARCHAR(500) NOT NULL,
        is_active BIT NOT NULL DEFAULT 1
    );
END;

/* ========================================================
   AUTH RESULT MAPPING FUNCTION
======================================================== */

IF OBJECT_ID('audit.fn_map_auth_result') IS NOT NULL
    DROP FUNCTION audit.fn_map_auth_result;
GO

CREATE FUNCTION audit.fn_is_valid_result_code
(
    @event_name NVARCHAR(200),
    @result_code NVARCHAR(50)
)
RETURNS BIT
AS
BEGIN
    RETURN (
        SELECT CASE 
            WHEN EXISTS (
                SELECT 1
                FROM audit.event_result_codes
                WHERE event_name = @event_name
                  AND result_code = @result_code
            )
            THEN 1 ELSE 0 END
    );
END;
GO

/* ========================================================
   CHECK CONSTRAINT (SAFE ADD)
======================================================== */

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_audit_events_valid_result_code'
)
BEGIN
    ALTER TABLE audit.audit_events
    ADD CONSTRAINT CK_audit_events_valid_result_code
    CHECK (audit.fn_is_valid_result_code(event_name, result_code) = 1);
END;
GO

CREATE PROCEDURE audit.usp_log_trace
(
    @correlation_id UNIQUEIDENTIFIER = NULL,
    @user_id        INT = NULL,
    @session_id     UNIQUEIDENTIFIER = NULL,
    @level          NVARCHAR(10),
    @action         NVARCHAR(200),
    @payload_json   NVARCHAR(MAX) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @level  = UPPER(LTRIM(RTRIM(@level)));
    SET @action = LTRIM(RTRIM(@action));

    IF @level NOT IN ('INFO', 'WARN', 'ERROR')
        THROW 51001, 'audit.usp_log_trace: invalid level.', 1;

    IF @action IS NULL OR @action = ''
        THROW 51002, 'audit.usp_log_trace: action is required.', 1;

    IF @payload_json IS NOT NULL AND ISJSON(@payload_json) <> 1
        THROW 51003, 'audit.usp_log_trace: payload must be valid JSON.', 1;

    INSERT INTO audit.trace_logs
    (
        occurred_at,
        correlation_id,
        user_id,
        session_id,
        level,
        action,
        payload_json
    )
    VALUES
    (
        SYSUTCDATETIME(),
        @correlation_id,
        @user_id,
        @session_id,
        @level,
        @action,
        @payload_json
    );
END;
GO

CREATE FUNCTION audit.fn_map_auth_result
(
    @result_code NVARCHAR(20)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        event_result_code =
            CASE
                WHEN @result_code = 'SUCAUTH01' THEN 'SUCCESS'

                WHEN @result_code = 'ERRAUTH01' THEN 'INVALID_PASSWORD'
                WHEN @result_code = 'ERRAUTH02' THEN 'USER_DISABLED'
                WHEN @result_code = 'ERRAUTH05' THEN 'ALREADY_LOGGED_IN'
                WHEN @result_code = 'ERRAUTH07' THEN 'USER_LOCKED'
                WHEN @result_code = 'ERRAUTH08' THEN 'USER_TERMINAL_LOCK'
                WHEN @result_code = 'ERRAUTH09' THEN 'PASSWORD_CHANGE_REQUIRED'

                ELSE 'ERROR'
            END,

        event_success =
            CASE
                WHEN @result_code = 'SUCAUTH01' THEN 1
                ELSE 0
            END
);
GO

CREATE FUNCTION audit.fn_map_user_result
(
    @result_code NVARCHAR(20)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        event_result_code =
            CASE
                WHEN @result_code = 'SUCAUTHUSR01' THEN 'SUCCESS'
                WHEN @result_code = 'ERRAUTHUSR01' THEN 'DUPLICATE_USERNAME'
                WHEN @result_code = 'ERRAUTHUSR04' THEN 'DUPLICATE_EMAIL'
                WHEN @result_code = 'ERRAUTHUSR02' THEN 'INVALID_ROLE'
                WHEN @result_code = 'ERRUSR01' THEN 'NOT_FOUND'
                WHEN @result_code = 'SUCUSR01' THEN 'SUCCESS'
                WHEN @result_code = 'ERRAUTH02' THEN 'NOT_FOUND'
                WHEN @result_code = 'SUCAUTH10' THEN 'SUCCESS'
                WHEN @result_code LIKE 'ERRAUTH%' THEN 'VALIDATION_FAILED'
                WHEN @result_code = 'SUCAUTH03' THEN 'SUCCESS'
                WHEN @result_code = 'ERRAUTH06' THEN 'NOT_FOUND'
                ELSE 'ERROR'
            END,

        event_success =
            CASE
                WHEN @result_code = 'SUCAUTHUSR01' THEN 1
                ELSE 0
            END
);
GO
