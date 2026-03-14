using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlUserCommandRepository : IUserCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly Guid _sessionId;
    private readonly int _userId;
    private readonly IErrorMessageResolver _messageResolver;
    private readonly ILogger _logger;

    public SqlUserCommandRepository(
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

    // --------------------------------------------------
    // Enable / Disable user
    // --------------------------------------------------

    public OperationResult EnableUser(int userId)
        => SetUserActive(userId, true);

    public OperationResult DisableUser(int userId)
        => SetUserActive(userId, false);

    private OperationResult SetUserActive(int targetUserId, bool isActive)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_set_user_active";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id", targetUserId);
        command.Parameters.AddWithValue("@is_active", isActive);

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

        command.ExecuteNonQuery();

        var code = resultCode.Value?.ToString() ?? "ERRPROC02";

        var message =
            friendlyMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var success =
            code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("User.SetActive", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                TargetUserId = targetUserId,
                IsActive = isActive,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("User.SetActive", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                TargetUserId = targetUserId,
                IsActive = isActive,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Logout user everywhere
    // --------------------------------------------------

    public OperationResult LogoutUserEverywhere(
        int targetUserId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_logout_user_everywhere";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id", targetUserId);
        command.Parameters.AddWithValue("@source_app", sourceApp);
        command.Parameters.AddWithValue("@source_client", sourceClient);
        command.Parameters.AddWithValue(
            "@source_ip",
            (object?)sourceIp ?? DBNull.Value);

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

        command.ExecuteNonQuery();

        var code = resultCode.Value?.ToString() ?? "ERRPROC02";

        var message =
            friendlyMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var success =
            code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("User.LogoutEverywhere", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                TargetUserId = targetUserId,
                SourceApp = sourceApp,
                SourceClient = sourceClient,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("User.LogoutEverywhere", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                TargetUserId = targetUserId,
                SourceApp = sourceApp,
                SourceClient = sourceClient,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Create user
    // --------------------------------------------------

    public OperationResult CreateUser(
        string username,
        string displayName,
        string roleName,
        string email,
        string password)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_create_user";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@username", username);
        command.Parameters.AddWithValue("@display_name", displayName);
        command.Parameters.AddWithValue("@role_name", roleName);
        command.Parameters.AddWithValue("@email", email);
        command.Parameters.AddWithValue("@password", password);

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

        command.ExecuteNonQuery();

        var code = resultCode.Value?.ToString() ?? "ERRAUTH03";

        var message =
            friendlyMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var success =
            code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("User.Create", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                Username = username,
                Role = roleName,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("User.Create", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                Username = username,
                Role = roleName,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Admin reset password
    // --------------------------------------------------

    public OperationResult ResetPasswordAsAdmin(
        int targetUserId,
        string newPassword)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_admin_reset_password";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(
            new SqlParameter("@target_user_id", SqlDbType.Int)
            { Value = targetUserId });

        command.Parameters.Add(
            new SqlParameter("@new_password", SqlDbType.NVarChar, 200)
            { Value = newPassword });

        var pCode = new SqlParameter("@result_code", SqlDbType.NVarChar, 20)
        {
            Direction = ParameterDirection.Output
        };

        var pMsg = new SqlParameter("@friendly_message", SqlDbType.NVarChar, 400)
        {
            Direction = ParameterDirection.Output
        };

        command.Parameters.Add(pCode);
        command.Parameters.Add(pMsg);

        command.ExecuteNonQuery();

        var code = pCode.Value?.ToString() ?? "ERRAUTH99";

        var message =
            pMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var success =
            code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("User.ResetPassword", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                TargetUserId = targetUserId,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("User.ResetPassword", new
            {
                PerformedBy = _userId,
                SessionId = _sessionId,
                TargetUserId = targetUserId,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }
}