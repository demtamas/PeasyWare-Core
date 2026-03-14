using Microsoft.Data.SqlClient;
using PeasyWare.Application.Dto;
using PeasyWare.Application.DTOs;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

public sealed class SqlSessionDetailsRepository : ISessionDetailsRepository
{
    private readonly SqlConnectionFactory _factory;

    public SqlSessionDetailsRepository(SqlConnectionFactory factory)
    {
        _factory = factory;
    }

    public SessionDetailsDto? GetSessionDetails(Guid sessionId)
    {
        using var conn = _factory.Create();
        conn.Open();

        using var cmd = conn.CreateCommand();
        cmd.CommandText = "auth.usp_get_session_details";
        cmd.CommandType = CommandType.StoredProcedure;

        cmd.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier)
            .Value = sessionId;

        using var reader = cmd.ExecuteReader();
        if (!reader.Read())
            return null;

        return new SessionDetailsDto
        {
            SessionId = reader.GetGuid("session_id"),
            IsActive = reader.GetBoolean("is_active"),
            LoginTime = reader.GetDateTime("login_time"),
            LastSeen = reader.GetDateTime("last_seen"),

            UserId = reader.GetInt32("user_id"),
            Username = reader.GetString("username"),
            DisplayName = reader.GetString("display_name"),

            ClientApp = reader["client_app"] as string,
            ClientInfo = reader["client_info"] as string,
            IpAddress = reader["ip_address"] as string,
            OsInfo = reader["os_info"] as string,

            CorrelationId = reader["correlation_id"] as string
        };
    }
}
