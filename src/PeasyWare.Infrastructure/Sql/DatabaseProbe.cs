using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Sql;

public sealed class DatabaseProbe
{
    private readonly SqlConnectionFactory _factory;

    public DatabaseProbe(SqlConnectionFactory factory)
    {
        _factory = factory;
    }

    public string GetConnectionInfo()
    {
        using var connection = _factory.Create();
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
                @@SERVERNAME       AS ServerName,
                DB_NAME()          AS DatabaseName,
                SYSTEM_USER        AS LoginName,
                GETUTCDATE()       AS UtcNow
        """;

        using var reader = command.ExecuteReader();
        reader.Read();

        return
            $"Server: {reader["ServerName"]}\n" +
            $"Database: {reader["DatabaseName"]}\n" +
            $"Login: {reader["LoginName"]}\n" +
            $"UTC (DB): {reader["UtcNow"]}";
    }
}
