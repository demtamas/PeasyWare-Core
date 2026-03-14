using System;
using System.Data;
using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlLoginRepository : ILoginRepository
{
    private readonly SqlConnectionFactory _factory;

    public SqlLoginRepository(SqlConnectionFactory factory)
    {
        _factory = factory;
    }

    public LoginResult Login(
        string username,
        string? password,
        LoginContext context)
    {
        // -----------------------------
        // HARD GUARDED DB BOUNDARY
        // -----------------------------

        var clientApp =
            string.IsNullOrWhiteSpace(context.ClientApp)
                ? "PeasyWare.UnknownClient"
                : context.ClientApp;

        var clientInfo =
            string.IsNullOrWhiteSpace(context.ClientInfo)
                ? Environment.MachineName
                : context.ClientInfo;

        var ipAddress =
            string.IsNullOrWhiteSpace(context.IpAddress)
                ? "UNKNOWN"
                : context.IpAddress;

        var osInfo =
            string.IsNullOrWhiteSpace(context.OsInfo)
                ? Environment.OSVersion.ToString()
                : context.OsInfo;

        using var connection = _factory.Create();
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_login";
        command.CommandType = CommandType.StoredProcedure;

        // Inputs (NEVER NULL for identity columns)
        command.Parameters.Add("@username", SqlDbType.NVarChar, 200).Value = username;
        command.Parameters.Add("@password_plain", SqlDbType.NVarChar, 400)
            .Value = (object?)password ?? DBNull.Value;

        command.Parameters.Add("@client_info", SqlDbType.NVarChar, 400).Value = clientInfo;
        command.Parameters.Add("@ip_address", SqlDbType.NVarChar, 100).Value = ipAddress;
        command.Parameters.Add("@client_app", SqlDbType.NVarChar, 100).Value = clientApp;
        command.Parameters.Add("@os_info", SqlDbType.NVarChar, 400).Value = osInfo;

        command.Parameters.Add("@force_login", SqlDbType.Bit).Value = context.ForceLogin;

        // Correlation (optional but safe)
        SqlCorrelation.Add(command);

        // Outputs
        var resultCode = command.Parameters.Add("@result_code", SqlDbType.NVarChar, 40);
        resultCode.Direction = ParameterDirection.Output;

        var friendlyMessage = command.Parameters.Add("@friendly_message", SqlDbType.NVarChar, 800);
        friendlyMessage.Direction = ParameterDirection.Output;

        var userId = command.Parameters.Add("@user_id_out", SqlDbType.Int);
        userId.Direction = ParameterDirection.Output;

        var sessionId = command.Parameters.Add("@session_id_out", SqlDbType.UniqueIdentifier);
        sessionId.Direction = ParameterDirection.Output;

        var displayName = command.Parameters.Add("@display_name_out", SqlDbType.NVarChar, 400);
        displayName.Direction = ParameterDirection.Output;

        var lastLogin = command.Parameters.Add("@last_login_time", SqlDbType.DateTime2);
        lastLogin.Direction = ParameterDirection.Output;

        var failedAttempts = command.Parameters.Add("@failed_attempts", SqlDbType.Int);
        failedAttempts.Direction = ParameterDirection.Output;

        var lockoutUntil = command.Parameters.Add("@lockout_until_out", SqlDbType.DateTime2);
        lockoutUntil.Direction = ParameterDirection.Output;

        command.ExecuteNonQuery();

        return new LoginResult
        {
            ResultCode = (string)resultCode.Value,
            FriendlyMessage = (string)friendlyMessage.Value,
            Success = ((string)resultCode.Value).StartsWith("SUC"),
            UserId = userId.Value == DBNull.Value ? null : (int?)userId.Value,
            SessionId = sessionId.Value == DBNull.Value ? null : (Guid?)sessionId.Value,
            DisplayName = displayName.Value as string,
            LastLoginTime = lastLogin.Value == DBNull.Value ? null : (DateTime?)lastLogin.Value,
            FailedAttempts = failedAttempts.Value == DBNull.Value ? 0 : (int)failedAttempts.Value,
            LockoutUntil = lockoutUntil.Value == DBNull.Value ? null : (DateTime?)lockoutUntil.Value
        };
    }
}
