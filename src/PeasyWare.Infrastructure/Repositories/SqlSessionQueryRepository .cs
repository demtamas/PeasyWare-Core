using PeasyWare.Application.DTOs;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using Microsoft.Data.SqlClient;

public sealed class SqlSessionQueryRepository : ISessionQueryRepository
{
    private readonly SqlConnectionFactory _factory;

    public SqlSessionQueryRepository(SqlConnectionFactory factory)
    {
        _factory = factory;
    }

    public IReadOnlyList<ActiveSessionDto> GetActiveSessions()
    {
        using var conn = _factory.Create();
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = @"
            SELECT
                session_id,
                username,
                client_app,
                client_info,
                last_seen,
                is_active
            FROM auth.v_active_sessions
            ORDER BY last_seen DESC";

        using var reader = cmd.ExecuteReader();

        var list = new List<ActiveSessionDto>();

        while (reader.Read())
        {
            list.Add(new ActiveSessionDto
            {
                SessionId = reader.GetGuid(0),
                Username = reader.GetString(1),
                ClientApp = reader.GetString(2),
                ClientInfo = reader.GetString(3),
                LastSeen = reader.GetDateTime(4),
                IsActive = reader.GetBoolean(5)
            });
        }

        return list;
    }
}
