-------------------------------------------
-- 3.3 EVENTS TABLE
-- Audit trail.
-------------------------------------------
GO

CREATE TABLE operations.setting_categories
(
    category        sysname        NOT NULL PRIMARY KEY,
    display_name    nvarchar(100)  NOT NULL,
    display_order   int            NOT NULL
);

INSERT INTO operations.setting_categories (category, display_name, display_order)
VALUES
('core','Core',10),
('auth','Authentication',20),
('inbound','Inbound',30),
('warehouse','Warehouse',40),
('logging','Logging',50),
('audit','Audit',60),
('client','Client',70);

-------------------------------------------
-- 3.2 Settings table
-- Central runtime configuration registry
-------------------------------------------
IF OBJECT_ID('operations.settings', 'U') IS NULL
BEGIN
    CREATE TABLE operations.settings
    (
        --------------------------------------------------
        -- Identity
        --------------------------------------------------

        setting_name        sysname            NOT NULL
            CONSTRAINT PK_operations_settings PRIMARY KEY,
        -- Internal key used by the application

        display_name        nvarchar(200)      NOT NULL,
        -- Human-readable label used in UI

        category            varchar(50)        NOT NULL
            CONSTRAINT DF_operations_settings_category DEFAULT ('general'),
        -- Logical grouping (auth, logging, inbound, pw, etc.)

        display_order       int                NOT NULL
            CONSTRAINT DF_operations_settings_display_order DEFAULT (100),
        -- Determines ordering within category in the UI

        --------------------------------------------------
        -- Value
        --------------------------------------------------

        setting_value       nvarchar(4000)     NULL,

        data_type           varchar(20)        NOT NULL
            CONSTRAINT CK_operations_settings_data_type
            CHECK (data_type IN ('string','int','bool','decimal','json')),

        --------------------------------------------------
        -- Validation rules (JSON metadata)
        --------------------------------------------------

        validation_rule     nvarchar(max)      NULL,
        /*
            JSON rule describing allowed values.

            Examples:

            {"type":"bool"}

            {"type":"enum","values":["TRACE","DEBUG","INFO","WARN","ERROR"]}

            {"type":"range","min":5,"max":240}

            {"type":"regex","pattern":"^[A-Z]{3}$"}
        */

        --------------------------------------------------
        -- Metadata
        --------------------------------------------------

        description         nvarchar(500)      NULL,

        is_sensitive        bit                NOT NULL
            CONSTRAINT DF_operations_settings_is_sensitive DEFAULT (0),
        -- Prevents displaying actual values in UI

        requires_restart    bit                NOT NULL
            CONSTRAINT DF_operations_settings_requires_restart DEFAULT (0),
        -- Indicates application restart is required

        --------------------------------------------------
        -- Audit fields
        --------------------------------------------------

        created_at          datetime2(3)       NOT NULL
            CONSTRAINT DF_operations_settings_created_at
            DEFAULT sysutcdatetime(),

        created_by          int                NULL
            CONSTRAINT DF_operations_settings_created_by
            DEFAULT CONVERT(int, SESSION_CONTEXT(N'user_id')),

        updated_at          datetime2(3)       NULL,

        updated_by          int                NULL
    );
END;
GO
