------------------------------------------------------------
-- Detect environment
------------------------------------------------------------
USE master;
GO

DECLARE @db sysname       = N'PW_Core_DEV';
DECLARE @os NVARCHAR(200) = LOWER(@@VERSION);
DECLARE @backupPath NVARCHAR(500);

IF @os LIKE '%windows%'
    SET @backupPath = 'C:\SQL_Backups\PW_Core_DEV.bak';
ELSE
    SET @backupPath = '/var/opt/mssql/backups/PW_Core_DEV.bak';

PRINT 'Environment: ' + @os;
PRINT 'Backup Path: ' + @backupPath;
PRINT '------------------------------------------------------------';


------------------------------------------------------------
-- Backup & Drop Existing DB
------------------------------------------------------------
IF DB_ID(@db) IS NOT NULL
BEGIN
    PRINT 'Backing up existing database [' + @db + ']...';

    BACKUP DATABASE [PW_Core_DEV]
        TO DISK = @backupPath
        WITH FORMAT, INIT, NAME = 'PW_Core_DEV Backup';

    PRINT 'Backup done. Dropping database...';

    ALTER DATABASE [PW_Core_DEV] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [PW_Core_DEV];

    PRINT 'Existing PW_Core_DEV dropped.';
END
ELSE
BEGIN
    PRINT 'No existing PW_Core_DEV found. Creating fresh database.';
END
PRINT '------------------------------------------------------------';
GO