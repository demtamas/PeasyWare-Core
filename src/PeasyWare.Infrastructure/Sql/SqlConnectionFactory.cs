using Microsoft.Data.SqlClient;
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
    // Plain connection (pre-login, read-only, jobs, etc.)
    // --------------------------------------------------
    public SqlConnection Create()
    {
        return new SqlConnection(_connectionString);
    }

    // --------------------------------------------------
    // Command connection WITH session + user context
    // --------------------------------------------------
    public SqlConnection CreateForCommand(
        Guid sessionId,
        int userId)
    {
        var connection = new SqlConnection(_connectionString);
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandType = CommandType.Text;
        command.CommandText = """
            EXEC sys.sp_set_session_context 
                @key = N'session_id',
                @value = @session_id;

            EXEC sys.sp_set_session_context 
                @key = N'user_id',
                @value = @user_id;
        """;

        command.Parameters.AddWithValue("@session_id", sessionId);
        command.Parameters.AddWithValue("@user_id", userId);

        //Console.WriteLine(connection.Database);
        //Console.WriteLine(connection.DataSource);

        command.ExecuteNonQuery();

        return connection;
    }
}
