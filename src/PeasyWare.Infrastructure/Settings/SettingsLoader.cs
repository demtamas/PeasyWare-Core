using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Settings;

/// <summary>
/// Loads immutable runtime configuration snapshot from operations.settings.
/// Values are read ONCE at application startup.
/// Missing or invalid settings cause startup failure.
/// </summary>
public sealed class SettingsLoader
{
    private readonly SqlConnectionFactory _factory;

    public SettingsLoader(SqlConnectionFactory factory)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
    }

    public RuntimeSettings Load()
    {
        var values = LoadRawSettings();

        // --------------------------------------------------
        // CORE
        // --------------------------------------------------

        var coreVersion = GetString(values, "core.version");
        var environment = GetString(values, "core.environment");

        // --------------------------------------------------
        // AUTHENTICATION
        // --------------------------------------------------

        var loginEnabled          = GetBool(values, "auth.login_enabled");
        var sessionTimeoutMinutes = GetInt(values, "auth.session_timeout_minutes");
        var appLockMinutes        = GetInt(values, "auth.app_lock_minutes");
        var maxLoginAttempts      = GetInt(values, "auth.max_login_attempts");
        var passwordMinLength     = GetInt(values, "auth.password_min_length");
        var passwordExpiryDays    = GetInt(values, "auth.password_expiry_days");
        var passwordHistoryDepth  = GetInt(values, "auth.password_history_depth");
        var auditEnabled          = GetBool(values, "audit.enabled");

        // --------------------------------------------------
        // LOGGING
        // --------------------------------------------------

        var loggingEnabled         = GetBool(values, "logging.enabled");
        var consoleLoggingEnabled  = GetBool(values, "logging.console.enabled");
        var databaseLoggingEnabled = GetBool(values, "logging.db.enabled");
        var includeSensitiveLogging = GetBool(values, "logging.include_sensitive");
        var minimumLogLevel        = GetEnum<LogLevel>(values, "logging.min_level");

        // --------------------------------------------------
        // UI MODE
        // --------------------------------------------------

        var defaultUiMode = GetEnum<UiMode>(values, "core.default_ui_mode");

        // --------------------------------------------------
        // CLIENT / SITE
        // --------------------------------------------------

        var warehouseCode = GetString(values, "pw.warehouse_code");
        var siteCode      = GetString(values, "pw.site_code");
        var siteName      = GetString(values, "pw.site_name");

        return new RuntimeSettings(
            coreVersion,
            environment,

            loggingEnabled,
            consoleLoggingEnabled,
            databaseLoggingEnabled,
            includeSensitiveLogging,
            minimumLogLevel,
            auditEnabled,
            defaultUiMode,

            sessionTimeoutMinutes,
            appLockMinutes,
            maxLoginAttempts,
            passwordMinLength,
            passwordExpiryDays,
            passwordHistoryDepth,
            loginEnabled,

            warehouseCode,
            siteCode,
            siteName
        );
    }

    // --------------------------------------------------
    // Raw loader (single DB hit)
    // --------------------------------------------------

    private Dictionary<string, string?> LoadRawSettings()
    {
        var result = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);

        using var conn = _factory.Create();
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = """
            SELECT setting_name, setting_value
            FROM operations.settings
            WHERE setting_value IS NOT NULL
        """;
        cmd.CommandType = CommandType.Text;

        using var reader = cmd.ExecuteReader();
        while (reader.Read())
        {
            result[reader.GetString(0)] = reader.GetString(1);
        }

        return result;
    }

    // --------------------------------------------------
    // Typed accessors (FAIL FAST)
    // --------------------------------------------------

    private static string GetString(
        IDictionary<string, string?> values,
        string key)
    {
        if (!values.TryGetValue(key, out var value) || string.IsNullOrWhiteSpace(value))
            throw new InvalidOperationException(
                $"Missing required setting '{key}'.");

        return value!;
    }

    private static int GetInt(
        IDictionary<string, string?> values,
        string key)
    {
        var raw = GetString(values, key);

        if (!int.TryParse(raw, out var result))
            throw new InvalidOperationException(
                $"Invalid integer value for setting '{key}': '{raw}'.");

        return result;
    }

    private static bool GetBool(
        IDictionary<string, string?> values,
        string key)
    {
        var raw = GetString(values, key);

        if (!bool.TryParse(raw, out var result))
            throw new InvalidOperationException(
                $"Invalid boolean value for setting '{key}': '{raw}'.");

        return result;
    }

    private static TEnum GetEnum<TEnum>(
        IDictionary<string, string?> values,
        string key)
        where TEnum : struct, Enum
    {
        var raw = GetString(values, key);

        if (!Enum.TryParse<TEnum>(raw, ignoreCase: true, out var result))
            throw new InvalidOperationException(
                $"Invalid enum value for setting '{key}': '{raw}'.");

        return result;
    }
}
