using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlUserSecurityRepository : IUserSecurityRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly IErrorMessageResolver _messageResolver;
    private readonly ILogger _logger;

    public SqlUserSecurityRepository(
        SqlConnectionFactory factory,
        IErrorMessageResolver messageResolver,
        ILogger logger)
    {
        _factory = factory;
        _messageResolver = messageResolver;
        _logger = logger;
    }

    public OperationResult ChangePassword(string username, string newPassword)
    {
        using var connection = _factory.Create();
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = "auth.usp_change_password";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@username", username);
        command.Parameters.AddWithValue("@new_password", newPassword);

        var resultCode = new SqlParameter("@result_code", SqlDbType.NVarChar, 20)
        {
            Direction = ParameterDirection.Output
        };

        var friendlyMsg = new SqlParameter("@friendly_message", SqlDbType.NVarChar, 400)
        {
            Direction = ParameterDirection.Output
        };

        command.Parameters.Add(resultCode);
        command.Parameters.Add(friendlyMsg);

        command.ExecuteNonQuery();

        var code = resultCode.Value?.ToString() ?? "ERRAUTH99";

        var message =
            friendlyMsg.Value?.ToString()
            ?? _messageResolver.Resolve(code);

        var success =
            code.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("User.ChangePassword", new
            {
                Username = username,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("User.ChangePassword", new
            {
                Username = username,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }
}