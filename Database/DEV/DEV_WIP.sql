USE PW_Core_DEV;
GO

-- Fix ERRTASK08 message template — remove {0} placeholder, use plain text
-- The bin code is now substituted by the calling flow where the context is known
UPDATE operations.error_messages
SET message_template = N'Wrong location scanned. Please scan the correct destination bin.'
WHERE error_code = N'ERRTASK08';
GO

PRINT 'ERRTASK08 message template updated.';
GO
