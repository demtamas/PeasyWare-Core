using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// Command repository for system settings.
///
/// Responsibilities:
/// - Updates operational settings
/// - Enforces session validity
/// - Relies on DB layer for validation + audit
/// - Logs execution results
/// </summary>
public sealed class SqlSettingsCommandRepository
    : RepositoryBase, ISettingsCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger _logger;

    public SqlSettingsCommandRepository(
        SqlConnectionFactory factory,
        SessionContext session,
        IErrorMessageResolver resolver,
        ILogger logger,
        SessionGuard sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory = factory;
        _session = session;
        _resolver = resolver;
        _logger = logger;

        if (_session.UserId == 0)
            throw new InvalidOperationException("Invalid session: UserId = 0");
    }

    // --------------------------------------------------
    // Update setting
    // --------------------------------------------------

    public OperationResult UpdateSetting(
        string settingName,
        string settingValue)
    {
        try
        {
            EnsureSession();

            using var connection = _factory.CreateForCommand(_session);
            using var command = connection.CreateCommand();

            command.CommandText = "operations.usp_setting_update";
            command.CommandType = CommandType.StoredProcedure;

            command.Parameters.Add(
                new SqlParameter("@setting_name", SqlDbType.NVarChar, 128)
                { Value = settingName });

            command.Parameters.Add(
                new SqlParameter("@setting_value", SqlDbType.NVarChar, 4000)
                { Value = settingValue });

            var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
            pCode.Direction = ParameterDirection.Output;

            var pMsg = command.Parameters.Add("@friendly_msg", SqlDbType.NVarChar, 400);
            pMsg.Direction = ParameterDirection.Output;

            command.ExecuteNonQuery();

            return BuildResult(
                action: "Settings.Update",
                resultCodeObj: pCode.Value,
                messageObj: pMsg.Value,
                context: new
                {
                    _session.UserId,
                    _session.SessionId,
                    _session.CorrelationId,
                    SettingName = settingName,
                    NewValue = settingValue
                });
        }
        catch (SessionExpiredException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.Error("Settings.Update.Exception", new
            {
                _session.UserId,
                _session.SessionId,
                ex.Message
            });

            return OperationResult.Create(
                false,
                "ERRSET99",
                "Unexpected error occurred while updating setting.");
        }
    }

    // --------------------------------------------------
    // Shared result builder
    // --------------------------------------------------

    private OperationResult BuildResult(
        string action,
        object? resultCodeObj,
        object? messageObj,
        object context)
    {
        var code = resultCodeObj?.ToString() ?? "ERRSET01";
        var message = messageObj?.ToString() ?? _resolver.Resolve(code);
        var success = code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info(action, new
            {
                context,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn(action, new
            {
                context,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }
}