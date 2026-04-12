using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// Session command repository.
/// Special case:
/// - No SessionGuard
/// - Used to detect expiry / logout
/// - CreateForCommand already applies session + correlation context
/// </summary>
public sealed class SqlSessionCommandRepository : ISessionCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;
    private readonly IErrorMessageResolver _messageResolver;
    private readonly ILogger _logger;

    public SqlSessionCommandRepository(
        SqlConnectionFactory factory,
        SessionContext session,
        IErrorMessageResolver messageResolver,
        ILogger logger)
    {
        _factory = factory;
        _session = session;
        _messageResolver = messageResolver;
        _logger = logger;
    }

    // --------------------------------------------------
    // Touch session (heartbeat)
    // --------------------------------------------------

    public SessionTouchResult TouchSession(
        Guid sessionId,
        string sourceApp,
        string sourceClient,
        string? sourceIp)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "auth.usp_session_touch";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value = sessionId;
        command.Parameters.Add("@source_app", SqlDbType.NVarChar, 50).Value = sourceApp;
        command.Parameters.Add("@source_client", SqlDbType.NVarChar, 200).Value = sourceClient;
        command.Parameters.Add("@source_ip", SqlDbType.NVarChar, 50).Value =
            (object?)sourceIp ?? DBNull.Value;

        var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
        pCode.Direction = ParameterDirection.Output;

        var pMessage = command.Parameters.Add("@friendly_msg", SqlDbType.NVarChar, 400);
        pMessage.Direction = ParameterDirection.Output;

        var pIsAlive = command.Parameters.Add("@is_alive", SqlDbType.Bit);
        pIsAlive.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        return new SessionTouchResult
        {
            ResultCode = pCode.Value?.ToString() ?? "ERRAUTH06",
            FriendlyMessage = pMessage.Value?.ToString() ?? string.Empty,
            IsAlive = pIsAlive.Value != DBNull.Value && (bool)pIsAlive.Value
        };
    }

    // --------------------------------------------------
    // Logout
    // --------------------------------------------------

    public OperationResult LogoutSession(
        Guid sessionId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "auth.usp_logout";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value = sessionId;
        command.Parameters.Add("@source_app", SqlDbType.NVarChar, 50).Value = sourceApp;
        command.Parameters.Add("@source_client", SqlDbType.NVarChar, 200).Value = sourceClient;
        command.Parameters.Add("@source_ip", SqlDbType.NVarChar, 50).Value =
            (object?)sourceIp ?? DBNull.Value;

        var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
        pCode.Direction = ParameterDirection.Output;

        var pMessage = command.Parameters.Add("@friendly_msg", SqlDbType.NVarChar, 400);
        pMessage.Direction = ParameterDirection.Output;

        var pSuccess = command.Parameters.Add("@success", SqlDbType.Bit);
        pSuccess.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        var code = pCode.Value?.ToString() ?? "ERRAUTH06";
        var message = pMessage.Value?.ToString() ?? _messageResolver.Resolve(code);
        var success = pSuccess.Value != DBNull.Value && (bool)pSuccess.Value;

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("Session.Logout", new
            {
                _session.UserId,
                _session.SessionId,
                SourceApp = sourceApp,
                SourceClient = sourceClient,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("Session.Logout", new
            {
                _session.UserId,
                _session.SessionId,
                SourceApp = sourceApp,
                SourceClient = sourceClient,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }
}