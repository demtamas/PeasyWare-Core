using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.DTOs;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Collections.Generic;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// QUERY repository for session-related reads.
///
/// Responsibilities:
/// - Read-only access to session data
/// - Uses SessionContext for DB tracing (SESSION_CONTEXT)
/// - No session enforcement (UI handles expired session)
/// </summary>
public sealed class SqlSessionQueryRepository : ISessionQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;

    public SqlSessionQueryRepository(
        SqlConnectionFactory factory,
        SessionContext session)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    // --------------------------------------------------
    // Get active sessions
    // --------------------------------------------------

    public IReadOnlyList<ActiveSessionDto> GetActiveSessions()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT
                session_id,
                username,
                client_app,
                client_info,
                last_seen,
                is_active
            FROM auth.v_active_sessions
            ORDER BY last_seen DESC
        """;

        using var reader = command.ExecuteReader();

        var result = new List<ActiveSessionDto>();

        while (reader.Read())
        {
            result.Add(MapActiveSession(reader));
        }

        return result;
    }

    // --------------------------------------------------
    // Mapping
    // --------------------------------------------------

    private static ActiveSessionDto MapActiveSession(SqlDataReader reader)
    {
        return new ActiveSessionDto
        {
            SessionId = reader.GetGuid(reader.GetOrdinal("session_id")),
            Username = reader.GetString(reader.GetOrdinal("username")),

            ClientApp = reader.IsDBNull(reader.GetOrdinal("client_app"))
                ? string.Empty
                : reader.GetString(reader.GetOrdinal("client_app")),

            ClientInfo = reader.IsDBNull(reader.GetOrdinal("client_info"))
                ? string.Empty
                : reader.GetString(reader.GetOrdinal("client_info")),

            LastSeen = reader.GetDateTime(reader.GetOrdinal("last_seen")),
            IsActive = reader.GetBoolean(reader.GetOrdinal("is_active"))
        };
    }
}