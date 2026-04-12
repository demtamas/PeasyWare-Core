using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Settings;
using PeasyWare.Infrastructure.Sql;
using System.Data;
using System.Text.Json;
using System.Text.Json.Serialization;

public sealed class InfrastructureLogger : ILogger
{
    private readonly RuntimeSettings _settings;
    private readonly SqlConnectionFactory _factory;
    private SessionContext? _session;

    public InfrastructureLogger(
        RuntimeSettings settings,
        SqlConnectionFactory factory)
    {
        _settings = settings;
        _factory = factory;
    }

    public void SetSession(SessionContext session)
    {
        _session = session;
    }

    // --------------------------------------------------------
    // Interface-required methods (simple wrappers)
    // --------------------------------------------------------

    public void Info(string message)
        => Log("INFO", message, null);

    public void Warn(string message)
        => Log("WARN", message, null);

    public void Error(string message)
        => Log("ERROR", message, null);

    public void Error(string message, Exception ex)
        => Log("ERROR", message, new
        {
            Exception = ex.Message,
            ex.StackTrace
        });

    public void Error(string message, Exception ex, object context)
        => Log("ERROR", message, new
        {
            Context = context,
            Exception = ex.Message,
            ex.StackTrace
        });

    // --------------------------------------------------------
    // New structured methods (preferred usage)
    // --------------------------------------------------------

    public void Info(string action, object? data)
        => Log("INFO", action, data);

    public void Warn(string action, object? data)
        => Log("WARN", action, data);

    public void Error(string action, object? data)
        => Log("ERROR", action, data);

    // --------------------------------------------------------
    // Core logging
    // --------------------------------------------------------

    private void Log(string level, string action, object? data)
    {
        if (!_settings.LoggingEnabled)
            return;

        try
        {
            using var connection = _factory.Create();
            connection.Open();

            using var command = connection.CreateCommand();
            command.CommandText = "audit.usp_log_trace";
            command.CommandType = CommandType.StoredProcedure;

            var payload = new
            {
                Timestamp = DateTime.UtcNow,
                Level = level,
                Action = action,
                Session = _session == null ? null : new
                {
                    _session.UserId,
                    _session.SessionId,
                    _session.CorrelationId,
                    _session.SourceApp,
                    _session.SourceClient
                },
                Data = data
            };

            var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
            {
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
            });

            command.Parameters.Add("@correlation_id", SqlDbType.UniqueIdentifier)
                .Value = ExtractCorrelationId(data)
                     ?? (object?)_session?.CorrelationId
                     ?? DBNull.Value;

            command.Parameters.Add("@user_id", SqlDbType.Int)
                .Value = _session is null ? DBNull.Value : _session.UserId;

            command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier)
                .Value = (object?)_session?.SessionId ?? DBNull.Value;

            command.Parameters.Add("@level", SqlDbType.NVarChar, 10)
                .Value = level;

            command.Parameters.Add("@action", SqlDbType.NVarChar, 200)
                .Value = action;

            command.Parameters.Add("@payload_json", SqlDbType.NVarChar, -1)
                .Value = json;

            command.ExecuteNonQuery();
        }
        catch (Exception ex)
        {
            Console.WriteLine("TRACE LOGGING FAILED: " + ex.Message);
        }
    }

    private static Guid? ExtractCorrelationId(object? data)
    {
        if (data == null)
            return null;

        var prop = data.GetType().GetProperty("CorrelationId");
        if (prop == null)
            return null;

        var value = prop.GetValue(data);

        return value is Guid g && g != Guid.Empty
            ? g
            : null;
    }
}