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

/********************************************************************************************
    PeasyWare WMS - Core Database Schema
    Version:        1.0.0
    Database:       PW_Core_DEV
    Description:    Single-file core schema + operational seed data
                    - Schemas
                    - Core tables
                    - Status & error lookup data
                    - Core stored procedures & helper functions

    Notes:
      - Intended for development and pre-production.
      - Test data (sample inbound, inventory, etc.) belongs in a SEPARATE script.
      - When production-ready, switch to migrations for structural changes.

********************************************************************************************/

-------------------------------------------
-- 1. Create / select database
-------------------------------------------
IF DB_ID('PW_Core_DEV') IS NULL
BEGIN
    CREATE DATABASE [PW_Core_DEV];
END;
GO

USE [PW_Core_DEV];
GO

-------------------------------------------
-- 2. Create schemas
-------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'auth')
    EXEC('CREATE SCHEMA auth');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'audit')
    EXEC('CREATE SCHEMA audit');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'inventory')
    EXEC('CREATE SCHEMA inventory');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'inbound')
    EXEC('CREATE SCHEMA inbound');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'locations')
    EXEC('CREATE SCHEMA locations');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'operations')
    EXEC('CREATE SCHEMA operations');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'core')
    EXEC('CREATE SCHEMA core');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'suppliers')
    EXEC('CREATE SCHEMA suppliers');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'customers')
    EXEC('CREATE SCHEMA customers');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'logistics')
    EXEC('CREATE SCHEMA logistics');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'warehouse')
    EXEC('CREATE SCHEMA warehouse');
GO

/********************************************************************************************
    3. OPERATIONS SCHEMA
    - Global settings
    - Friendly error messages
    - Error log
    - Core helpers (session user, friendly message lookup)
********************************************************************************************/

-------------------------------------------
-- 3.1 Settings categories table
-- Central runtime configuration registry
-------------------------------------------
GO
