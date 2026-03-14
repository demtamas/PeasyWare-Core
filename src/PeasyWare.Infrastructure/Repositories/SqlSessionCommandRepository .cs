using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlSessionCommandRepository : ISessionCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly Guid _sessionId;
    private readonly int _userId;
    private readonly IErrorMessageResolver _messageResolver;
    private readonly ILogger _logger;
    private SqlConnectionFactory connectionFactory;
    private IErrorMessageResolver errorMessageResolver;

    public SqlSessionCommandRepository(
        SqlConnectionFactory factory,
        Guid sessionId,
        int userId,
        IErrorMessageResolver messageResolver,
        ILogger logger)
    {
        _factory = factory;
        _sessionId = sessionId;
        _userId = userId;
        _messageResolver = messageResolver;
        _logger = logger;
    }

    public SqlSessionCommandRepository(SqlConnectionFactory connectionFactory, Guid sessionId, int userId, IErrorMessageResolver errorMessageResolver)
    {
        this.connectionFactory = connectionFactory;
        _sessionId = sessionId;
        _userId = userId;
        this.errorMessageResolver = errorMessageResolver;
    }

    // --------------------------------------------------
    // Session keep-alive
    // --------------------------------------------------

    public SessionTouchResult TouchSession(Guid sessionId)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_session_touch";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(
            "@session_id",
            SqlDbType.UniqueIdentifier).Value = sessionId;

        var resultCode = command.Parameters.Add(
            "@result_code",
            SqlDbType.NVarChar,
            20);
        resultCode.Direction = ParameterDirection.Output;

        var friendlyMsg = command.Parameters.Add(
            "@friendly_msg",
            SqlDbType.NVarChar,
            400);
        friendlyMsg.Direction = ParameterDirection.Output;

        var isAlive = command.Parameters.Add(
            "@is_alive",
            SqlDbType.Bit);
        isAlive.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        var code = resultCode.Value?.ToString() ?? "ERRAUTH06";

        var message =
            friendlyMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var alive = isAlive.Value is true;

        var result = new SessionTouchResult
        {
            IsAlive = alive,
            ResultCode = code,
            FriendlyMessage = message
        };

        if (alive)
        {
            _logger.Info("Session.Touch", new
            {
                UserId = _userId,
                SessionId = _sessionId,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("Session.Touch", new
            {
                UserId = _userId,
                SessionId = _sessionId,
                ResultCode = code,
                Success = false
            });
        }

        return result;
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
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_logout";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@session_id", sessionId);
        command.Parameters.AddWithValue("@source_app", sourceApp);
        command.Parameters.AddWithValue("@source_client", sourceClient);
        command.Parameters.AddWithValue(
            "@source_ip",
            (object?)sourceIp ?? DBNull.Value);

        SqlCorrelation.Add(command);

        var resultCode = command.Parameters.Add(
            "@result_code",
            SqlDbType.NVarChar,
            20);
        resultCode.Direction = ParameterDirection.Output;

        var friendlyMsg = command.Parameters.Add(
            "@friendly_msg",
            SqlDbType.NVarChar,
            400);
        friendlyMsg.Direction = ParameterDirection.Output;

        var successParam = command.Parameters.Add(
            "@success",
            SqlDbType.Bit);
        successParam.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        var code = resultCode.Value?.ToString() ?? "ERRAUTH06";

        var message =
            friendlyMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var success = successParam.Value is true;

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("Session.Logout", new
            {
                UserId = _userId,
                SessionId = _sessionId,
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
                UserId = _userId,
                SessionId = _sessionId,
                SourceApp = sourceApp,
                SourceClient = sourceClient,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }
}