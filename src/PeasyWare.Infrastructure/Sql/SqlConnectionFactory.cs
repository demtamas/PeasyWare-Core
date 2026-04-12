using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Sql;

public sealed class SqlConnectionFactory
{
    private readonly string _connectionString;

    public SqlConnectionFactory(string connectionString)
    {
        _connectionString = connectionString;
    }

    // --------------------------------------------------
    // Plain connection (rare use)
    // --------------------------------------------------

    public SqlConnection Create()
    {
        return new SqlConnection(_connectionString);
    }

    // --------------------------------------------------
    // Command connection WITH session context
    // --------------------------------------------------

    public SqlConnection CreateForCommand(SessionContext session)
    {
        var connection = new SqlConnection(_connectionString);
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandType = CommandType.Text;
        command.CommandText = """
            EXEC sys.sp_set_session_context @key = N'session_id', @value = @session_id;
            EXEC sys.sp_set_session_context @key = N'user_id', @value = @user_id;
            EXEC sys.sp_set_session_context @key = N'source_app', @value = @source_app;
            EXEC sys.sp_set_session_context @key = N'source_client', @value = @source_client;
            EXEC sys.sp_set_session_context @key = N'source_ip', @value = @source_ip;
            EXEC sys.sp_set_session_context @key = N'correlation_id', @value = @correlation_id;
        """;

        command.Parameters.Add(new SqlParameter("@session_id", SqlDbType.UniqueIdentifier)
        {
            Value = session.SessionId
        });

        command.Parameters.Add("@user_id", SqlDbType.Int)
            .Value = session.UserId;

        command.Parameters.Add("@source_app", SqlDbType.NVarChar, 100)
            .Value = session.SourceApp;

        command.Parameters.Add("@source_client", SqlDbType.NVarChar, 200)
            .Value = session.SourceClient;

        command.Parameters.Add("@source_ip", SqlDbType.NVarChar, 50)
            .Value = (object?)session.SourceIp ?? DBNull.Value;

        command.Parameters.Add("@correlation_id", SqlDbType.UniqueIdentifier)
            .Value = (object?)session.CorrelationId ?? DBNull.Value;

        command.ExecuteNonQuery();

        return connection;
    }
}