IF @data_type IS NULL
        BEGIN
            SET @result_code = 'ERRSET01';
            SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- Validation
        --------------------------------------------------------

        IF @data_type = 'int'
           AND TRY_CONVERT(int, @setting_value) IS NULL
        BEGIN
            SET @result_code = 'ERRSET02';
            SET @friendly_msg = operations.fn_get_friendly_message(@result_code);
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- SAFE session context resolution
        --------------------------------------------------------

        SELECT
            @session_id_raw =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'session_id')),

            @correlation_id_raw =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'correlation_id')),

            @user_id =
                TRY_CONVERT(int, SESSION_CONTEXT(N'user_id')),

            @source_app =
                TRY_CONVERT(nvarchar(100), SESSION_CONTEXT(N'source_app')),

            @source_client =
                TRY_CONVERT(nvarchar(200), SESSION_CONTEXT(N'source_client')),

            @source_ip =
                TRY_CONVERT(nvarchar(50), SESSION_CONTEXT(N'source_ip'));

        SET @session_id =
            TRY_CONVERT(uniqueidentifier, @session_id_raw);

        SET @correlation_id =
            TRY_CONVERT(uniqueidentifier, @correlation_id_raw);

        --------------------------------------------------------
        -- HARD GUARD
        --------------------------------------------------------

        IF @session_id IS NULL OR @user_id IS NULL
        BEGIN
            SET @result_code = 'ERRCTX01';
            SET @friendly_msg = 'Invalid or missing session context';
            ROLLBACK;
            RETURN;
        END;

        --------------------------------------------------------
        -- Update
        --------------------------------------------------------

        UPDATE operations.settings
        SET
            setting_value = @setting_value,
            updated_at = SYSUTCDATETIME(),
            updated_by = @user_id
        WHERE setting_name = @setting_name;

        --------------------------------------------------------
        -- Structured audit
        --------------------------------------------------------

        INSERT INTO audit.setting_changes
        (
            setting_name,
            old_value,
            new_value,
            changed_at,
            changed_by,
            source_app,
            source_client,
            source_ip,
            correlation_id
        )
        VALUES
        (
            @setting_name,
            @old_value,
            @setting_value,
            SYSUTCDATETIME(),
            @user_id,
            @source_app,
            @source_client,
            @source_ip,
            @correlation_id
        );

        --------------------------------------------------------
        -- Event audit
        --------------------------------------------------------

        DECLARE @payload_json NVARCHAR(MAX);

        SET @payload_json = (
            SELECT
                @setting_name  AS SettingName,
                @old_value     AS OldValue,
                @setting_value AS NewValue
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id,
            @event_name     = 'system.setting.updated',
            @result_code    = 'SUCCESS',
            @success        = 1,
            @payload_json   = @payload_json;

        COMMIT;

        SET @result_code = 'SUCSET01';
        SET @friendly_msg = operations.fn_get_friendly_message(@result_code);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;

        --------------------------------------------------------
        -- Capture error FIRST (this was missing)
        --------------------------------------------------------

        DECLARE @error nvarchar(4000) = ERROR_MESSAGE();

        DECLARE @payload_json_error NVARCHAR(MAX);

        SET @payload_json_error = (
            SELECT
                @error AS ErrorMessage,
                ERROR_NUMBER() AS ErrorNumber,
                ERROR_LINE() AS ErrorLine
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC audit.usp_log_event
            @correlation_id = @correlation_id,
            @user_id        = @user_id,
            @session_id     = @session_id,
            @event_name     = 'system.error.occurred',
            @result_code    = 'UNHANDLED_EXCEPTION',
            @success        = 0,
            @payload_json   = @payload_json_error;

        SET @result_code = 'ERRSET99';
        SET @friendly_msg = 'Unexpected error occurred while updating setting.';
    END CATCH
END
GO

IF NOT EXISTS (SELECT 1 FROM operations.error_messages WHERE error_code = N'ERRAUTH01')
BEGIN
    INSERT INTO operations.error_messages
        (error_code, module_code, severity, message_template, tech_messege)
    VALUES
        (N'ERRAUTH01', N'AUTH', N'ERROR',
            N'Invalid username or password.',
            N'Auth: Credentials invalid'),

        (N'ERRAUTH02', N'AUTH', N'ERROR',
            N'Your account is blocked. Please contact your system administrator.',
            N'Auth: Account inactive or blocked'),

        (N'ERRAUTH03', N'AUTH', N'ERROR', 
            N'Login is currently disabled for this site.',
            N'Auth: Global login disabled'),

        (N'ERRAUTH04', N'AUTH', N'ERROR',
            N'Your password has expired. Please reset your password.',
            N'Auth: Password expired'),

        (N'ERRAUTH05', N'AUTH', N'ERROR',
            N'You are already logged in on another session.',
            N'Auth: Concurrent session exists'),

        (N'ERRAUTH06', N'AUTH', N'ERROR',
            N'Your session is no longer active. Please log in again.',
            N'Auth: Session inactive/expired'),

        (N'ERRAUTH07', N'AUTH', N'ERROR',
            N'Too many failed attempts. Please try again later.',
            N'Auth: Lockout threshold reached'),

        (N'ERRAUTH08', N'AUTH', N'ERROR',
            N'Invalid credentials. Login temporarily locked.',
            N'Auth: Progressive lockout'),

        (N'ERRAUTH09', N'AUTH', N'WARN',
            N'Your password has expired. You must change it.',
            N'Auth: Mandatory password change'),

        (N'ERRAUTH10', N'AUTH', N'WARN',
            N'New password does not meet complexity requirements.',
            N'Auth: Complexity rules failed'),

        (N'ERRAUTH11', N'AUTH', N'WARN',
            N'New password must differ from your recent passwords.',
            N'Auth: Password reuse detected'),

        (N'SUCAUTH01', N'AUTH', N'INFO',
            N'Login successful. Welcome back!',
            N'Auth: Login OK'),

        (N'SUCAUTH02', N'AUTH', N'INFO',
            N'Session refreshed successfully.',
            N'Auth: Session heartbeat OK'),

        (N'SUCAUTH03', N'AUTH', N'INFO',
            N'Logout successful.',
            N'Auth: Session closed'),

        (N'SUCAUTH10', N'AUTH', N'INFO',
            N'Password changed successfully.',
            N'Auth: Password updated'),

        (N'ERRAUTHUSR01', N'AUTH', N'ERROR',
            N'A user with this username already exists.',
            N'Auth.CreateUser: Duplicate username'),

        (N'ERRAUTHUSR02', N'AUTH', N'ERROR',
            N'The selected role does not exist.',
            N'Auth.CreateUser: Invalid role'),

        (N'ERRAUTHUSR03', N'AUTH', N'ERROR',
            N'User creation failed due to a system error.',
            N'Auth.CreateUser: Insert failed'),

        (N'WARAUTHUSR01', N'AUTH', N'WARN',
            N'The password is valid but considered weak.',
            N'Auth.CreateUser: Weak password'),

        (N'ERRAUTHUSR04', N'AUTH', N'ERROR',
            N'A user with this email address already exists.',
            N'Auth.CreateUser: Duplicate email'),

        (N'SUCAUTHUSR01', N'AUTH', N'INFO',
            N'User account created successfully.',
            N'Auth.CreateUser: Success'),

        (N'ERRINB01', N'INB', N'ERROR',
            N'Inbound delivery not found.',
            N'Inbound.Activate: inbound_id not found'),

        (N'ERRINB02', N'INB', N'ERROR',
            N'Inbound delivery is already activated.',
            N'Inbound.Activate: already ACTIVATED'),

        (N'ERRINB03', N'INB', N'ERROR',
            N'Inbound delivery has no lines and cannot be activated.',
            N'Inbound.Activate: no inbound_lines exist'),

        (N'ERRINB04', N'INB', N'ERROR',
            N'Inbound delivery is cancelled and cannot be activated.',
            N'Inbound.Activate: inbound_status = CANCELLED'),

        (N'ERRINB05', N'INB', N'ERROR',
            N'Inbound delivery is not in a valid state for this operation.',
            N'Inbound: invalid inbound_status transition'),

        (N'SUCINB01', N'INB', N'INFO',
            N'Inbound delivery activated successfully.',
            N'Inbound.Activate: success'),

        (N'SUCINBCLS01',     N'INB', N'INFO',
            N'Inbound delivery fully received and closed.',
            N'Inbound.Header: auto-closed after final receipt'),

        (N'SUCINBREOPEN01',  N'INB', N'INFO',
            N'Inbound delivery reopened following receipt reversal.',
            N'Inbound.Header: reopened after reversal'),

        (N'ERRINBL01', N'INB', N'ERROR',
            N'Inbound line not found.',
            N'Inbound.Line: inbound_line_id not found'),

        (N'ERRINBL03', N'INB', N'ERROR',
            N'Inbound line is already fully received.',
            N'Inbound.Line: already RECEIVED'),

        (N'SUCINBL01', N'INB', N'INFO',
            N'Inbound line received successfully.',
            N'Inbound.Line: receipt success'),

        (N'ERRINBL02', N'INB', N'ERROR',
            N'Receiving quantity must be greater than zero.',
            N'Inbound.Line: invalid quantity <= 0'),

        (N'ERRINBL04', N'INB', N'ERROR',
            N'Inbound is not in a receivable state.',
            N'Inbound.Header: not ACTIVATED or RECEIVING'),

        (N'ERRINBL05', N'INB', N'ERROR',
            N'Invalid or inactive staging bin.',
            N'Inbound.Line: staging bin invalid'),

        (N'ERRINBL99', N'INB', N'ERROR',
            N'Unexpected error while receiving inbound line.',
            N'Inbound.Line: unhandled exception'),

        (N'ERRSSCC01', N'SSCC', N'ERROR',
            N'SSCC not recognised. Please verify the barcode and try again.',
            N'SSCC.Validate: SSCC not found'),

        (N'ERRSSCC02', N'SSCC', N'ERROR',
            N'SSCC already exists and is currently active.',
            N'SSCC.Validate: duplicate active SSCC'),

        (N'ERRSSCC03', N'SSCC', N'ERROR',
            N'SSCC is already linked to another inbound delivery.',
            N'SSCC.Validate: linked to different inbound'),

        (N'ERRSSCC04', N'SSCC', N'ERROR',
            N'SSCC cannot be reused while active. Complete or cancel the previous transaction first.',
            N'SSCC.Validate: reuse blocked - active record exists'),

        (N'ERRSSCC05', N'SSCC', N'WARN',
            N'SSCC reuse is allowed only for returned units. Please confirm return process.',
            N'SSCC.Validate: reuse requires return context'),

        (N'ERRQTY01', N'INB', N'ERROR',
            N'Received quantity exceeds expected quantity for this inbound line.',
            N'Inbound.Line: quantity > expected'),

        (N'ERRQTY03', N'INB', N'ERROR',
            N'Unit of measure mismatch. Please use the expected UOM for this material.',
            N'Inbound.Line: UOM mismatch'),

        (N'ERRQTY04', N'INB', N'ERROR',
            N'Full handling unit quantity required for this SSCC.',
            N'Inbound.Line: partial HU not allowed'),

        (N'ERRMAT01', N'INB', N'ERROR',
            N'Material could not be resolved from the scanned GTIN.',
            N'Inbound.Line: GTIN resolution failed'),

        (N'ERRMAT02', N'INB', N'ERROR',
            N'Material is not expected on this inbound delivery.',
            N'Inbound.Line: material not on inbound'),

        (N'ERRMAT03', N'INB', N'ERROR',
            N'Multiple materials match this GTIN. Manual selection required.',
            N'Inbound.Line: ambiguous GTIN mapping'),

        (N'ERRMAT04', N'INB', N'ERROR',
            N'Material master data incomplete. Please contact master data team.',
            N'Inbound.Line: material master incomplete'),

        (N'ERRPROC01', N'CORE', N'ERROR',
            N'Operation not allowed in current document status.',
            N'Process.Validate: invalid status transition'),

        (N'ERRPROC02', N'CORE', N'ERROR',
            N'Transaction validation failed. Please review the scanned data.',
            N'Process.Validate: business rule failure'),

        (N'ERRPROC03', N'CORE', N'ERROR',
            N'Another user is currently processing this document.',
            N'Process.Locking: record locked'),

        (N'ERRPROC04', N'CORE', N'INFO',
            N'Process cancelled. No changes were saved.',
            N'Process: user cancelled transaction'),

        (N'ERRSSCC06', N'SSCC', N'ERROR',
            N'SSCC has already been received for this inbound delivery.',
            N'SSCC.Validate: already received on same inbound'),

        (N'ERRINB06', N'INB', N'ERROR',
            N'Inbound delivery is already fully received and closed.',
            N'Inbound.Receive: attempt after CLOSED'),

        (N'SUCSSCC01', N'SSCC', N'INFO',
            N'SSCC validated successfully. Please scan again to confirm receipt.',
            N'SSCC.Validate: claim acquired'),

        (N'ERRSSCC07', N'SSCC', N'ERROR',
             N'SSCC is currently being processed by another user.',
             N'SSCC.Receive: active claim held by different session'),

        (N'ERRSSCC08', N'SSCC', N'ERROR',
             N'SSCC confirmation window expired. Please rescan to validate again.',
             N'SSCC.Receive: claim expired'),

        (N'ERRSSCC09', N'SSCC', N'ERROR',
             N'SSCC confirmation token invalid. Please rescan to validate again.',
             N'SSCC.Receive: claim token mismatch'),

        (N'ERRSSCC99', N'SSCC', N'ERROR',
             N'SSCC validation failed. Please rescan. If it persists, contact a supervisor.',
             N'SSCC.Preview: unexpected system error'),

        (N'ERRINBHYB01', N'INBOUND', N'ERROR',
            N'Inbound structure invalid. Please contact warehouse supervisor',
            N'Inbound.Activate: hybrid SSCC + manual structure detected'),

        (N'ERRINBMODE01', N'INBOUND', N'ERROR',
            N'Inbound mode already determined and cannot be changed.',
            N'Inbound.Activate: attempted mode overwrite'),

        (N'ERRINBSTRUCT01', N'INBOUND', N'ERROR',
             N'Inbound structure cannot be modified after activation.',
             N'Inbound.Structure: modification attempted after activation'),

        (N'ERRINBSTRUCT02', N'INBOUND', N'ERROR',
             N'Expected handling units cannot be modified after activation.',
             N'Inbound.Structure: expected units modification attempted after activation'),

        (N'SUCINBREV01',  N'INB', N'INFO',
            N'Receipt reversed successfully.',
            N'Inbound.Reversal: success'),

        (N'ERRINBREV01',  N'INB', N'ERROR',
            N'Receipt not found or has already been reversed.',
            N'Inbound.Reversal: receipt_id not found or is_reversal=1'),

        (N'ERRINBREV02',  N'INB', N'ERROR',
            N'This receipt has already been reversed.',
            N'Inbound.Reversal: reversed_receipt_id already set'),

        (N'ERRINBREV03',  N'INB', N'ERROR',
            N'Inventory unit could not be reversed. Unit may have been moved or modified.',
            N'Inbound.Reversal: inventory_units UPDATE rowcount=0'),

        (N'ERRINBREV99',  N'INB', N'ERROR',
            N'Unexpected error during reversal. Please contact your supervisor.',
            N'Inbound.Reversal: unhandled exception in CATCH'),

        (N'ERRTASK01', N'TASK', N'ERROR',
             N'Inventory unit not recognised.',
             N'Task.Create: inventory unit not found'),

        (N'ERRTASK02', N'TASK', N'ERROR',
             N'Inventory unit not eligible for putaway.',
             N'Task.Create: inventory unit state invalid for putaway'),

        (N'ERRTASK03', N'TASK', N'ERROR',
             N'Inventory unit is not located in a staging bin.',
             N'Task.Create: staging placement not found'),

        (N'ERRTASK04', N'TASK', N'ERROR',
             N'No suitable storage location found. Please contact a supervisor.',
             N'Task.Create: destination bin suggestion failed'),

        (N'ERRTASK05', N'TASK', N'ERROR',
             N'A warehouse task already exists for this unit.',
             N'Task.Create: duplicate active task detected'),

        (N'ERRTASK06', N'TASK', N'ERROR',
             N'Task claim is no longer valid. Please rescan.',
             N'Task.Claim: claim expired or invalid'),

        (N'ERRTASK07', N'TASK', N'ERROR',
             N'Task cannot be confirmed in its current state.',
             N'Task.Confirm: invalid state transition'),

        (N'ERRTASK99', N'TASK', N'ERROR',
             N'Warehouse task operation failed. Please retry. If the problem persists, contact a supervisor.',
             N'Task.Engine: unexpected system error'),

        (N'SUCTASK02', N'TASK', N'SUCCESS',
            N'Putaway completed successfully.',
            N'Task.Confirm: putaway confirmed'),

        (N'ERRSET01', N'SET', N'ERROR',
            N'Setting not found.',
            N'Settings.Update: requested setting does not exist'),

        (N'ERRSET02', N'SET', N'ERROR',
            N'The provided value is not valid for this setting type.',
            N'Settings.Update: data type validation failed'),

        (N'ERRSET03', N'SET', N'ERROR',
            N'The value is not allowed for this setting.',
            N'Settings.Update: value not in allowed_values list'),

        (N'ERRSET04', N'SET', N'ERROR',
            N'The value is outside the permitted range.',
            N'Settings.Update: numeric range validation failed'),

        (N'SUCSET01', N'SET', N'SUCCESS',
            N'Setting updated successfully.',
            N'Settings.Update: value persisted'),

        (N'SUCTASK01', N'TASK', N'SUCCESS',
        N'Putaway task created. Please move stock to the suggested location.',
        N'Task.Create: task created and destination bin reserved'),

        (N'ERRTASK08', N'TASK', N'ERROR',
            N'Wrong location. Please move the stock to {0}.',
            N'Task.Confirm: scanned bin does not match reserved destination'),

        (N'ERRTASK09', N'TASK', N'ERROR',
            N'The suggested location is no longer available. Please request a new suggestion.',
            N'Task.Confirm: destination bin capacity exceeded or bin inactive at confirm time'),

        /* ── ERRINBL06/07/08 — previously missing message definitions ── */
        (N'ERRINBL06', N'INB', N'ERROR',
            N'Received quantity must be greater than zero.',
            N'Inbound.Line (manual mode): received_qty NULL or <= 0'),

        (N'ERRINBL07', N'INB', N'ERROR',
            N'Staging bin must be provided.',
            N'Inbound.Line: staging_bin_code parameter is NULL or empty'),

        (N'ERRINBL08', N'INB', N'ERROR',
            N'Staging bin not found or is inactive. Please check the bin code and try again.',
            N'Inbound.Line: staging_bin_code not found in locations.bins or is_active = 0'),

        /* ── ERRINBL09/10 — BBE and batch mismatch hard blocks ── */
        (N'ERRINBL09', N'INB', N'ERROR',
            N'Best Before Date on label does not match the expected value. Please contact your supervisor.',
            N'Inbound.Line (SSCC mode): scanned best_before_date != expected_unit.best_before_date'),

        (N'ERRINBL10', N'INB', N'ERROR',
            N'Batch number on label does not match the expected value. Please contact your supervisor.',
            N'Inbound.Line (SSCC mode): scanned batch_number != expected_unit.batch_number');

END;
GO

/* ============================================================
   AUTHENTICATION LAYER v1.0
   Schemas, tables, settings, helper procs, auth SPs
   ============================================================*/

---------------------------------------------------------------
-- 0. Ensure db
---------------------------------------------------------------
USE [PW_Core_DEV];
GO

---------------------------------------------------------------
-- 1.4 Get Roles
---------------------------------------------------------------
GO

-------------------------------------------
-- 3.4 Error messages (friendly messages)
-- Core place for human-friendly messages by error_code & module
-------------------------------------------
IF OBJECT_ID('operations.error_messages', 'U') IS NULL
BEGIN
    CREATE TABLE operations.error_messages
    (
        error_code        nvarchar(20)    NOT NULL PRIMARY KEY,   -- e.g. ERRINB01, SUCINB01
        module_code       nvarchar(20)    NOT NULL,               -- e.g. INB, INV, SYS
        severity          nvarchar(10)    NOT NULL,               -- INFO/WARN/ERROR/CRIT
        message_template  nvarchar(400)   NOT NULL,               -- Friendly text (with optional {placeholders})
        is_active         bit             NOT NULL DEFAULT (1),

        tech_messege      nvarchar(400)    NULL,                   -- optional technical message for logs
        created_at        datetime2(3)    NOT NULL CONSTRAINT DF_operations_error_messages_created_at DEFAULT (sysutcdatetime()),
        created_by        int             NULL     CONSTRAINT DF_operations_error_messages_created_by DEFAULT (CONVERT(int, SESSION_CONTEXT(N'user_id'))),
        updated_at        datetime2(3)    NULL,
        updated_by        int             NULL
    );
END;
GO

-------------------------------------------
-- 3.3 Error log
-- Captures errors with context for troubleshooting
-------------------------------------------
IF OBJECT_ID('operations.error_log', 'U') IS NULL
BEGIN
    CREATE TABLE operations.error_log
    (
        id               bigint           IDENTITY(1,1) PRIMARY KEY,
        error_code       nvarchar(20)     NULL,          -- may be null for unknown errors
        module_code      nvarchar(20)     NULL,
        message          nvarchar(400)    NULL,
        details          nvarchar(max)    NULL,          -- stack, inner exceptions, etc.
        context_json     nvarchar(max)    NULL,          -- optional JSON context payload
        correlation_id   uniqueidentifier NOT NULL CONSTRAINT DF_operations_error_log_corrid DEFAULT (NEWSEQUENTIALID()),
        occurred_at      datetime2(3)     NOT NULL CONSTRAINT DF_operations_error_log_occurred_at DEFAULT (sysutcdatetime()),
        user_id          int              NULL           -- from SESSION_CONTEXT('user_id') if available
    );
END;
GO

ALTER PROCEDURE operations.usp_set_session_user
    @user_id int
AS
BEGIN
    SET NOCOUNT ON;

    EXEC sys.sp_set_session_context @key = N'user_id', @value = @user_id;
END;
GO

ALTER FUNCTION operations.fn_get_session_user_id()
RETURNS int
AS
BEGIN
    DECLARE @uid_sql_variant sql_variant;
    DECLARE @uid int;

    SELECT @uid_sql_variant = SESSION_CONTEXT(N'user_id');
    IF @uid_sql_variant IS NOT NULL
    BEGIN
        SET @uid = TRY_CONVERT(int, @uid_sql_variant);
    END

    RETURN @uid;
END;
GO

ALTER FUNCTION operations.fn_get_friendly_message
(
    @error_code nvarchar(20)
)
RETURNS nvarchar(400)
AS
BEGIN
    DECLARE @msg nvarchar(400);

    SELECT @msg = em.message_template
    FROM operations.error_messages em
    WHERE em.error_code = @error_code
      AND em.is_active = 1;
    RETURN ISNULL(@msg, @error_code);
END;
GO

ALTER PROCEDURE operations.usp_log_error
(
    @error_code     nvarchar(20) = NULL,
    @module_code    nvarchar(20) = NULL,
    @message        nvarchar(400) = NULL,
    @details        nvarchar(max) = NULL,
    @context_json   nvarchar(max) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @user_id int = operations.fn_get_session_user_id();

    INSERT INTO operations.error_log
        (error_code, module_code, message, details, context_json, user_id)
    VALUES
        (@error_code, @module_code, @message, @details, @context_json, @user_id);
END;
GO

/* ============================================================
   1. TABLES
   ============================================================*/

---------------------------------------------------------------
-- 1.1 Users
---------------------------------------------------------------
IF OBJECT_ID('auth.users', 'U') IS NULL
BEGIN
    CREATE TABLE auth.users
    (
        id                   INT IDENTITY(1,1) PRIMARY KEY,
        username             NVARCHAR(100)  NOT NULL UNIQUE,
        display_name         NVARCHAR(200)  NOT NULL,
        email                NVARCHAR(255)  NULL UNIQUE,
        is_active            BIT            NOT NULL DEFAULT (1),

        password_hash        VARBINARY(512) NULL,
        salt                 VARBINARY(256) NOT NULL,
        password_last_changed DATETIME2(0)  NOT NULL DEFAULT SYSUTCDATETIME(),
        password_expires_at   DATETIME2(0)  NOT NULL DEFAULT '9999-12-31T00:00:00',
        must_change_password  BIT           NOT NULL DEFAULT 0,

        failed_attempts      INT            NOT NULL DEFAULT 0,
        lockout_until        DATETIME2(3)   NULL,

        is_2fa_enabled       BIT            NOT NULL DEFAULT 0,
        twofa_secret         VARBINARY(512) NULL,

        created_at           DATETIME2(3)   NOT NULL CONSTRAINT DF_auth_users_created_at DEFAULT (SYSUTCDATETIME()),
        created_by           INT            NULL     CONSTRAINT DF_auth_users_created_by DEFAULT (CONVERT(INT, SESSION_CONTEXT(N'user_id'))),
        updated_at           DATETIME2(3)   NULL,
        updated_by           INT            NULL
    );
END;
GO

-- Add is_system_role to support system/api role filtering
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('auth.roles')
      AND name = 'is_system_role'
)
BEGIN
    ALTER TABLE auth.roles
    ADD is_system_role BIT NOT NULL DEFAULT 0;
END;
GO

---------------------------------------------------------------
-- 1.3 User → Roles
---------------------------------------------------------------
IF OBJECT_ID('auth.user_roles', 'U') IS NULL
BEGIN
    CREATE TABLE auth.user_roles
    (
        user_id INT NOT NULL,
        role_id INT NOT NULL,
        PRIMARY KEY (user_id, role_id),

        CONSTRAINT FK_user_roles_user FOREIGN KEY (user_id)
            REFERENCES auth.users(id),

        CONSTRAINT FK_user_roles_role FOREIGN KEY (role_id)
            REFERENCES auth.roles(id)
    );
END;
GO
