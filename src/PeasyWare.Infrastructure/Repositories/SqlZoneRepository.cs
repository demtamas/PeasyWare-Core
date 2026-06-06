using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlZoneRepository : RepositoryBase, IZoneRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlZoneRepository(
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

    public IReadOnlyList<ZoneDto> GetZones(bool includeInactive = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = $"""
            SELECT zone_id, zone_code, zone_name, description, is_active,
                   created_at, created_by_username, updated_at, updated_by_username,
                   total_bins, active_bins
            FROM locations.v_zones
            {(includeInactive ? "" : "WHERE is_active = 1")}
            ORDER BY zone_code
            """;

        using var reader = command.ExecuteReader();
        var results = new List<ZoneDto>();
        while (reader.Read())
        {
            results.Add(new ZoneDto
            {
                ZoneId            = reader.GetInt32(0),
                ZoneCode          = reader.GetString(1),
                ZoneName          = reader.GetString(2),
                Description       = reader.IsDBNull(3)  ? null : reader.GetString(3),
                IsActive          = reader.GetBoolean(4),
                CreatedAt         = reader.GetDateTime(5),
                CreatedByUsername = reader.IsDBNull(6)  ? null : reader.GetString(6),
                UpdatedAt         = reader.IsDBNull(7)  ? null : reader.GetDateTime(7),
                UpdatedByUsername = reader.IsDBNull(8)  ? null : reader.GetString(8),
                TotalBins         = reader.GetInt32(9),
                ActiveBins        = reader.GetInt32(10)
            });
        }
        return results;
    }

    public OperationResult CreateZone(string zoneCode, string zoneName, string? description = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_create_zone";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@zone_code",   SqlDbType.NVarChar, 50)  { Value = zoneCode });
        command.Parameters.Add(new SqlParameter("@zone_name",   SqlDbType.NVarChar, 100) { Value = zoneName });
        command.Parameters.Add(new SqlParameter("@description", SqlDbType.NVarChar, 255) { Value = (object?)description ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Zone.Create", "ERRZON99", new { ZoneCode = zoneCode });
        return BuildResult("Zone.Create", reader.GetString(1), new { ZoneCode = zoneCode });
    }

    public OperationResult UpdateZone(string zoneCode, string? zoneName = null, string? description = null, bool clearDesc = false)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_update_zone";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@zone_code",   SqlDbType.NVarChar, 50)  { Value = zoneCode });
        command.Parameters.Add(new SqlParameter("@zone_name",   SqlDbType.NVarChar, 100) { Value = (object?)zoneName    ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@description", SqlDbType.NVarChar, 255) { Value = (object?)description ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_desc",  SqlDbType.Bit)            { Value = clearDesc });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Zone.Update", "ERRZON99", new { ZoneCode = zoneCode });
        return BuildResult("Zone.Update", reader.GetString(1), new { ZoneCode = zoneCode });
    }

    public OperationResult DeactivateZone(string zoneCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_deactivate_zone";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@zone_code", SqlDbType.NVarChar, 50) { Value = zoneCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Zone.Deactivate", "ERRZON99", new { ZoneCode = zoneCode });
        return BuildResult("Zone.Deactivate", reader.GetString(1), new { ZoneCode = zoneCode });
    }

    public OperationResult ReactivateZone(string zoneCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_reactivate_zone";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@zone_code", SqlDbType.NVarChar, 50) { Value = zoneCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Zone.Reactivate", "ERRZON99", new { ZoneCode = zoneCode });
        return BuildResult("Zone.Reactivate", reader.GetString(1), new { ZoneCode = zoneCode });
    }

    public OperationResult DeleteZone(string zoneCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_delete_zone";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@zone_code", SqlDbType.NVarChar, 50) { Value = zoneCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Zone.Delete", "ERRZON99", new { ZoneCode = zoneCode });
        return BuildResult("Zone.Delete", reader.GetString(1), new { ZoneCode = zoneCode });
    }
}
