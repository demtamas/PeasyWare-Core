USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE auth.sp_hash_password
(
    @plain NVARCHAR(200),
    @salt  VARBINARY(256) OUTPUT,
    @hash  VARBINARY(512) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @plain IS NULL
    BEGIN
        SET @salt = NULL;
        SET @hash = NULL;
        RETURN;
    END;

    -- 32 bytes of cryptographic salt
    SET @salt = CRYPT_GEN_RANDOM(32);

    SET @hash = HASHBYTES('SHA2_512',
                CONVERT(VARBINARY(512), @plain) + @salt);
END;
GO

/* ============================================================
   3. SESSION CLEANUP
   ============================================================*/
GO
