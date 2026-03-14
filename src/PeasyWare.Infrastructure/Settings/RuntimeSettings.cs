namespace PeasyWare.Infrastructure.Settings;

/// <summary>
/// Immutable snapshot of runtime configuration loaded at application start.
/// Values originate from operations.settings and MUST NOT change during runtime.
/// 
/// Any change to these settings requires application restart to take effect.
/// This is a deliberate design choice.
/// </summary>
public sealed class RuntimeSettings
{
    // --------------------------------------------------
    // Core
    // --------------------------------------------------

    public string CoreVersion { get; }
    public string Environment { get; }

    // --------------------------------------------------
    // Logging
    // --------------------------------------------------

    public bool LoggingEnabled { get; }
    public bool ConsoleLoggingEnabled { get; }
    public bool DatabaseLoggingEnabled { get; }
    public bool IncludeSensitiveLogging { get; }
    public bool AuditEnabled { get; }
    public LogLevel MinimumLogLevel { get; }

    // --------------------------------------------------
    // Receiving
    // --------------------------------------------------

    public ReceivingUiMode ReceivingUiMode { get; }

    // --------------------------------------------------
    // Authentication
    // --------------------------------------------------

    public int SessionTimeoutMinutes { get; }
    public int AppLockMinutes { get; }
    public int MaxLoginAttempts { get; }
    public int PasswordMinLength { get; }
    public int PasswordExpiryDays { get; }
    public int PasswordHistoryDepth { get; }
    public bool LoginEnabled { get; }

    // --------------------------------------------------
    // Client / Site
    // --------------------------------------------------

    public string WarehouseCode { get; }
    public string SiteCode { get; }
    public string SiteName { get; }
    public bool DiagnosticsEnabled { get; set; }

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------

    public RuntimeSettings(
        string coreVersion,
        string environment,

        bool loggingEnabled,
        bool consoleLoggingEnabled,
        bool databaseLoggingEnabled,
        bool includeSensitiveLogging,
        LogLevel minimumLogLevel,
        bool auditEnabled,
        ReceivingUiMode receivingUiMode,

        int sessionTimeoutMinutes,
        int appLockMinutes,
        int maxLoginAttempts,
        int passwordMinLength,
        int passwordExpiryDays,
        int passwordHistoryDepth,
        bool loginEnabled,

        string warehouseCode,
        string siteCode,
        string siteName)
    {
        CoreVersion = coreVersion;
        Environment = environment;

        LoggingEnabled = loggingEnabled;
        ConsoleLoggingEnabled = consoleLoggingEnabled;
        DatabaseLoggingEnabled = databaseLoggingEnabled;
        IncludeSensitiveLogging = includeSensitiveLogging;
        MinimumLogLevel = minimumLogLevel;
        AuditEnabled = auditEnabled;

        ReceivingUiMode = receivingUiMode;

        SessionTimeoutMinutes = sessionTimeoutMinutes;
        AppLockMinutes = appLockMinutes;
        MaxLoginAttempts = maxLoginAttempts;
        PasswordMinLength = passwordMinLength;
        PasswordExpiryDays = passwordExpiryDays;
        PasswordHistoryDepth = passwordHistoryDepth;
        LoginEnabled = loginEnabled;

        WarehouseCode = warehouseCode;
        SiteCode = siteCode;
        SiteName = siteName;
    }
}

/// <summary>
/// Ordered severity levels for runtime logging.
/// </summary>
public enum LogLevel
{
    Info = 1,
    Warn = 2,
    Error = 3
}

/// <summary>
/// Receiving UI presentation modes.
/// </summary>
public enum ReceivingUiMode
{
    Minimal = 1,
    Trace = 2
}
