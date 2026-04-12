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
/// Command repository for user-related operations.
/// 
/// GOLD STANDARD:
/// - One DB call → one audit event
/// - Logging ONLY after DB execution
/// - No duplicate / trace noise
/// - Clean, business-level actions
/// </summary>
public sealed class SqlUserCommandRepository
    : RepositoryBase, IUserCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger _logger;

    public SqlUserCommandRepository(
        SqlConnectionFactory factory,
        SessionContext session,
        IErrorMessageResolver resolver,
        ILogger logger,
        SessionGuard sessionGuard)
        : base(sessionGuard, session.SessionId)
    {
        _factory = factory;
        _session = session;
        _resolver = resolver;
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
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "auth.usp_set_user_active";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@user_id", SqlDbType.Int).Value = targetUserId;
        command.Parameters.Add("@is_active", SqlDbType.Bit).Value = isActive;

        var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
        pCode.Direction = ParameterDirection.Output;

        var pMsg = command.Parameters.Add("@friendly_msg", SqlDbType.NVarChar, 400);
        pMsg.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        return BuildResult(
            action: "user.status.updated",
            resultCodeObj: pCode.Value,
            messageObj: pMsg.Value,
            operation: new
            {
                PerformedBy = _session.UserId,
                TargetUserId = targetUserId,
                IsActive = isActive
            });
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
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "auth.usp_logout_user_everywhere";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@user_id", SqlDbType.Int).Value = targetUserId;
        command.Parameters.Add("@source_app", SqlDbType.NVarChar, 50).Value = sourceApp;
        command.Parameters.Add("@source_client", SqlDbType.NVarChar, 200).Value = sourceClient;
        command.Parameters.Add("@source_ip", SqlDbType.NVarChar, 50).Value =
            (object?)sourceIp ?? DBNull.Value;

        var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
        pCode.Direction = ParameterDirection.Output;

        var pMsg = command.Parameters.Add("@friendly_msg", SqlDbType.NVarChar, 400);
        pMsg.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        return BuildResult(
            action: "user.session.terminated",
            resultCodeObj: pCode.Value,
            messageObj: pMsg.Value,
            operation: new
            {
                PerformedBy = _session.UserId,
                TargetUserId = targetUserId,
                SourceApp = sourceApp,
                SourceClient = sourceClient
            });
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
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "auth.usp_create_user";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@username", SqlDbType.NVarChar, 200).Value = username;
        command.Parameters.Add("@display_name", SqlDbType.NVarChar, 200).Value = displayName;
        command.Parameters.Add("@role_name", SqlDbType.NVarChar, 100).Value = roleName;
        command.Parameters.Add("@email", SqlDbType.NVarChar, 200).Value = email;
        command.Parameters.Add("@password", SqlDbType.NVarChar, 400).Value = password;

        var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
        pCode.Direction = ParameterDirection.Output;

        var pMsg = command.Parameters.Add("@friendly_msg", SqlDbType.NVarChar, 400);
        pMsg.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        return BuildResult(
            action: "user.created",
            resultCodeObj: pCode.Value,
            messageObj: pMsg.Value,
            operation: new
            {
                PerformedBy = _session.UserId,
                Username = username,
                Role = roleName
            });
    }

    // --------------------------------------------------
    // Admin reset password
    // --------------------------------------------------

    public OperationResult ResetPasswordAsAdmin(
        int targetUserId,
        string newPassword)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "auth.usp_admin_reset_password";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@target_user_id", SqlDbType.Int).Value = targetUserId;
        command.Parameters.Add("@new_password", SqlDbType.NVarChar, 200).Value = newPassword;

        var pCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 20);
        pCode.Direction = ParameterDirection.Output;

        var pMsg = command.Parameters.Add("@friendly_message", SqlDbType.NVarChar, 400);
        pMsg.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        return BuildResult(
            action: "user.password.reset",
            resultCodeObj: pCode.Value,
            messageObj: pMsg.Value,
            operation: new
            {
                PerformedBy = _session.UserId,
                TargetUserId = targetUserId
            });
    }

    // --------------------------------------------------
    // Shared result builder (GOLD STANDARD)
    // --------------------------------------------------

    private OperationResult BuildResult(
    string action,
    object? resultCodeObj,
    object? messageObj,
    object operation)
    {
        var code = resultCodeObj?.ToString() ?? "ERRPROC02";

        var message =
            messageObj?.ToString()
            ?? _resolver.Resolve(code);

        var success =
            string.Equals(code, "SUCCESS", StringComparison.OrdinalIgnoreCase)
            || code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        // TRACE ONLY (post execution)
        _logger.Info(action, new
        {
            ResultCode = code,
            Success = success,
            Operation = operation
        });

        return result;
    }
}