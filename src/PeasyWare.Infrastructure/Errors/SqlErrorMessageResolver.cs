using Microsoft.Data.SqlClient;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Collections.Generic;

namespace PeasyWare.Infrastructure.Errors;

public sealed class SqlErrorMessageResolver : IErrorMessageResolver
{
    private readonly Dictionary<string, string> _messages;

    public SqlErrorMessageResolver(SqlConnectionFactory factory)
    {
        _messages = new Dictionary<string, string>();

        using var connection = factory.Create();
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = @"
            SELECT error_code, message_template
            FROM operations.error_messages
            WHERE is_active = 1";

        using var reader = command.ExecuteReader();

        while (reader.Read())
        {
            var code = reader.GetString(0);
            var message = reader.GetString(1);

            _messages[code] = message;
        }
    }

    public string Resolve(string errorCode)
    {
        return _messages.TryGetValue(errorCode, out var message)
            ? message
            : $"No friendly message found for: {errorCode}";
    }
}