using Microsoft.Data.SqlClient;
using PeasyWare.Application.Interfaces;
using PeasyWare.Domain;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlUserRepository : IUserRepository
{
    private readonly SqlConnectionFactory _factory;

    public SqlUserRepository(SqlConnectionFactory factory)
    {
        _factory = factory;
    }

    public User? GetByUsername(string username)
    {
        using var connection = _factory.Create();
        connection.Open();

        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT u.id, u.username, u.is_active
            FROM auth.users AS u
            WHERE u.username = @username;
        """;

        command.Parameters.AddWithValue("@username", username);

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            return null;

        var colId       = reader.GetOrdinal("id");
        var colUsername = reader.GetOrdinal("username");
        var colActive   = reader.GetOrdinal("is_active");

        return new User(
            reader.GetInt32(colId),
            reader.GetString(colUsername),
            reader.GetBoolean(colActive)
        );
    }
}
