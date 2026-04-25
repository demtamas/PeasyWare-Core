PRINT 'inbound.usp_create_inbound created.';
GO

-- ── 3. inbound.usp_create_inbound_line ──────────────────────────────────
GO

CREATE OR ALTER PROCEDURE inbound.usp_activate_inbound
(
    @inbound_id INT,
    @user_id INT = NULL,
    @session_id UNIQUEIDENTIFIER = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @current_status      VARCHAR(3),
        @existing_mode       VARCHAR(6),
        @sscc_line_count     INT,
        @manual_line_count   INT,
        @mode_code           VARCHAR(6);

    BEGIN TRY
        BEGIN TRAN;

        SELECT
            @current_status = inbound_status_code,
            @existing_mode  = inbound_mode_code
        FROM inbound.inbound_deliveries WITH (UPDLOCK, HOLDLOCK)
        WHERE inbound_id = @inbound_id;

        IF @current_status IS NULL
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM inbound.inbound_status_transitions
            WHERE from_status_code = @current_status
              AND to_status_code   = 'ACT'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB05' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF NOT EXISTS
        (
            SELECT 1
            FROM inbound.inbound_lines
            WHERE inbound_id = @inbound_id
              AND line_state_code <> 'CNL'
        )
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINB03' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        SELECT
            @sscc_line_count = COUNT(DISTINCT l.inbound_line_id)
        FROM inbound.inbound_lines l
        JOIN inbound.inbound_expected_units eu
            ON eu.inbound_line_id = l.inbound_line_id
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL';

        SELECT
            @manual_line_count = COUNT(*)
        FROM inbound.inbound_lines l
        WHERE l.inbound_id = @inbound_id
          AND l.line_state_code <> 'CNL'
          AND NOT EXISTS (
                SELECT 1
                FROM inbound.inbound_expected_units eu
                WHERE eu.inbound_line_id = l.inbound_line_id
          );

        IF @sscc_line_count > 0 AND @manual_line_count > 0
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBHYB01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        IF @sscc_line_count > 0
            SET @mode_code = 'SSCC';
        ELSE
            SET @mode_code = 'MANUAL';

        IF @existing_mode IS NOT NULL AND @existing_mode <> @mode_code
        BEGIN
            SELECT CAST(0 AS BIT) AS success, N'ERRINBMODE01' AS result_code, NULL AS inbound_id;
            ROLLBACK;
            RETURN;
        END

        EXEC sys.sp_set_session_context @key = N'user_id',    @value = @user_id;
        EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;

        UPDATE inbound.inbound_deliveries
        SET inbound_status_code = 'ACT',
            inbound_mode_code   = @mode_code,
            updated_at          = SYSUTCDATETIME(),
            updated_by          = @user_id
        WHERE inbound_id = @inbound_id;

        COMMIT;

        SELECT CAST(1 AS BIT) AS success, N'SUCINB01' AS result_code, @inbound_id AS inbound_id;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SELECT CAST(0 AS BIT) AS success, N'ERRINB99' AS result_code, NULL AS inbound_id;
    END CATCH
END;
GO

GO

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
