USE PW_Core_DEV;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- Add lock support to locations.bins
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('locations.bins') AND name = 'is_locked')
BEGIN
    ALTER TABLE locations.bins
        ADD is_locked      BIT           NOT NULL DEFAULT (0),
            locked_by      INT           NULL,
            locked_at      DATETIME2(3)  NULL,
            locked_reason  NVARCHAR(255) NULL;

    PRINT 'locations.bins: lock columns added.';
END
ELSE
    PRINT 'locations.bins: lock columns already exist, skipped.';
GO
