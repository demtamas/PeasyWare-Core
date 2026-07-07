using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlClientRepository : RepositoryBase, IClientRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlClientRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory = factory;
        _session = session;
    }

    public IReadOnlyList<ClientDto> GetClients(bool includeInactive = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = $"""
            SELECT client_name, session_timeout_minutes, max_concurrent_sessions,
                   is_active, description, created_at, created_by_username
            FROM auth.v_clients
            {(includeInactive ? "" : "WHERE is_active = 1")}
            ORDER BY client_name
            """;

        using var reader = command.ExecuteReader();
        var list = new List<ClientDto>();
        while (reader.Read())
        {
            list.Add(new ClientDto
            {
                ClientName            = reader.GetString(0),
                SessionTimeoutMinutes = reader.IsDBNull(1) ? null : reader.GetInt32(1),
                MaxConcurrentSessions = reader.IsDBNull(2) ? null : reader.GetInt32(2),
                IsActive              = reader.GetBoolean(3),
                Description           = reader.IsDBNull(4) ? null : reader.GetString(4),
                CreatedAt             = reader.GetDateTime(5),
                CreatedByUsername     = reader.IsDBNull(6) ? null : reader.GetString(6)
            });
        }
        return list;
    }

    public OperationResult CreateClient(string clientName, int? sessionTimeoutMinutes = null, int? maxConcurrentSessions = null, string? description = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "auth.usp_create_client";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@client_name",              SqlDbType.NVarChar, 100) { Value = clientName });
        command.Parameters.Add(new SqlParameter("@session_timeout_minutes",  SqlDbType.Int)           { Value = (object?)sessionTimeoutMinutes  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@max_concurrent_sessions",  SqlDbType.Int)           { Value = (object?)maxConcurrentSessions  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@description",              SqlDbType.NVarChar, 255) { Value = (object?)description           ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Client.Create", "ERRCLI99", new { ClientName = clientName });
        return BuildResult("Client.Create", reader.GetString(1), new { ClientName = clientName });
    }

    public OperationResult UpdateClient(string clientName, int? sessionTimeoutMinutes = null, bool clearTimeout = false, int? maxConcurrentSessions = null, bool clearMaxSessions = false, string? description = null, bool clearDesc = false)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "auth.usp_update_client";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@client_name",              SqlDbType.NVarChar, 100) { Value = clientName });
        command.Parameters.Add(new SqlParameter("@session_timeout_minutes",  SqlDbType.Int)           { Value = (object?)sessionTimeoutMinutes  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_timeout",            SqlDbType.Bit)           { Value = clearTimeout });
        command.Parameters.Add(new SqlParameter("@max_concurrent_sessions",  SqlDbType.Int)           { Value = (object?)maxConcurrentSessions  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_max_sessions",       SqlDbType.Bit)           { Value = clearMaxSessions });
        command.Parameters.Add(new SqlParameter("@description",              SqlDbType.NVarChar, 255) { Value = (object?)description           ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_desc",               SqlDbType.Bit)           { Value = clearDesc });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Client.Update", "ERRCLI99", new { ClientName = clientName });
        return BuildResult("Client.Update", reader.GetString(1), new { ClientName = clientName });
    }

    public OperationResult DeactivateClient(string clientName)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "auth.usp_deactivate_client";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@client_name", SqlDbType.NVarChar, 100) { Value = clientName });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Client.Deactivate", "ERRCLI99", new { ClientName = clientName });
        return BuildResult("Client.Deactivate", reader.GetString(1), new { ClientName = clientName });
    }

    public OperationResult ReactivateClient(string clientName)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "auth.usp_reactivate_client";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@client_name", SqlDbType.NVarChar, 100) { Value = clientName });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Client.Reactivate", "ERRCLI99", new { ClientName = clientName });
        return BuildResult("Client.Reactivate", reader.GetString(1), new { ClientName = clientName });
    }
}
