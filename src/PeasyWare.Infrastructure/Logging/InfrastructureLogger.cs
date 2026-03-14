using Microsoft.Data.SqlClient;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Settings;
using PeasyWare.Infrastructure.Sql;
using System.Data;
using System.Text.Json;

namespace PeasyWare.Infrastructure.Logging;

public sealed class InfrastructureLogger : ILogger
{
    private readonly RuntimeSettings _settings;
    private readonly SqlConnectionFactory _connectionFactory;

    public InfrastructureLogger(
        RuntimeSettings settings,
        SqlConnectionFactory connectionFactory)
    {
        _settings = settings;
        _connectionFactory = connectionFactory;
    }

    public void Info(string message) => Write(LogLevel.Info, message, null);
    public void Info(string message, object data) => Write(LogLevel.Info, message, data);

    public void Warn(string message) => Write(LogLevel.Warn, message, null);
    public void Warn(string message, object data) => Write(LogLevel.Warn, message, data);

    public void Error(string message) => Write(LogLevel.Error, message, null);
    public void Error(string message, object data) => Write(LogLevel.Error, message, data);

    public void Error(string message, Exception exception)
        => Write(LogLevel.Error, $"{message} | {exception}", null);

    public void Error(string message, Exception exception, object data)
        => Write(LogLevel.Error, $"{message} | {exception}", data);

    private void Write(LogLevel level, string message, object? data)
    {
        //Console.WriteLine("[DEBUG] AuditEnabled = " + _settings.AuditEnabled);

        if (!_settings.LoggingEnabled)
            return;

        if (level < _settings.MinimumLogLevel)
            return;

        if (_settings.ConsoleLoggingEnabled)
            WriteToConsole(level, message, data);

        if (_settings.AuditEnabled &&
            message != "Auth.LoginAttempt" &&
            message != "Session.Touch" &&
            message != "Session.Logout" &&
            message != "Auth.LoginSuccess" &&
            message != "Auth.PasswordChangeSuccess" &&
            message != "Auth.PasswordChangeFailed")
        {
            var resultCode = ExtractResultCode(data);
            var success = ExtractSuccess(data);

            WriteAudit(message, resultCode, success, data);
        }
    }
    private static string ExtractResultCode(object? data)
    {
        if (data is null) return "UNKNOWN";

        var prop = data.GetType().GetProperty("ResultCode");
        return prop?.GetValue(data)?.ToString() ?? "UNKNOWN";
    }

    private static bool ExtractSuccess(object? data)
    {
        if (data is null) return false;

        var prop = data.GetType().GetProperty("Success");
        return prop?.GetValue(data) is bool b && b;
    }

    private static void WriteToConsole(LogLevel level, string message, object? data)
    {
        var prefix = level switch
        {
            LogLevel.Info => "[INFO]",
            LogLevel.Warn => "[WARN]",
            LogLevel.Error => "[ERROR]",
            _ => "[LOG]"
        };

        var correlationPart = CorrelationContext.Current is not null
            ? $" [corr:{CorrelationContext.Current}]"
            : string.Empty;

        var dataPart = data is null
            ? string.Empty
            : " " + JsonSerializer.Serialize(data);

        Console.WriteLine($"{prefix}{correlationPart} {message}{dataPart}");
    }
    private void WriteAudit(
    string eventName,
    string resultCode,
    bool success,
    object? data)
    {
        try
        {
            using var connection = _connectionFactory.Create();
            connection.Open();

            using var command = connection.CreateCommand();
            command.CommandText = @"
        INSERT INTO audit.audit_events
        (
            correlation_id,
            user_id,
            session_id,
            event_name,
            result_code,
            success,
            payload_json
        )
        VALUES
        (
            @corr,
            @user_id,
            @session_id,
            @event_name,
            @result_code,
            @success,
            @payload
        );";

            command.Parameters.AddWithValue(
                "@corr",
                (object?)CorrelationContext.Current ?? DBNull.Value);

            command.Parameters.AddWithValue(
                "@user_id",
                ExtractValue(data, "UserId") ?? (object)DBNull.Value);

            command.Parameters.AddWithValue(
                "@session_id",
                ExtractValue(data, "SessionId") ?? (object)DBNull.Value);

            command.Parameters.AddWithValue("@event_name", eventName);
            command.Parameters.AddWithValue("@result_code", resultCode);
            command.Parameters.AddWithValue("@success", success);

            command.Parameters.AddWithValue(
                "@payload",
                data is null
                    ? DBNull.Value
                    : JsonSerializer.Serialize(data));

            command.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            Console.WriteLine("[AUDIT ERROR] " + ex.Message);
        }
    }

    private static object? ExtractValue(object? data, string propertyName)
    {
        if (data is null) return null;

        var prop = data.GetType().GetProperty(propertyName);
        return prop?.GetValue(data);
    }
}