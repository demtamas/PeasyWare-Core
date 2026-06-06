using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlSectionRepository : RepositoryBase, ISectionRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlSectionRepository(
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

    public IReadOnlyList<SectionDto> GetSections(bool includeInactive = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = $"""
            SELECT storage_section_id, section_code, section_name, description, is_active,
                   created_at, created_by_username, updated_at, updated_by_username,
                   total_bins, active_bins
            FROM locations.v_sections
            {(includeInactive ? "" : "WHERE is_active = 1")}
            ORDER BY section_code
            """;

        using var reader = command.ExecuteReader();
        var results = new List<SectionDto>();
        while (reader.Read())
        {
            results.Add(new SectionDto
            {
                SectionId         = reader.GetInt32(0),
                SectionCode       = reader.GetString(1),
                SectionName       = reader.GetString(2),
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

    public OperationResult CreateSection(string sectionCode, string sectionName, string? description = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_create_section";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@section_code", SqlDbType.NVarChar, 50)  { Value = sectionCode });
        command.Parameters.Add(new SqlParameter("@section_name", SqlDbType.NVarChar, 100) { Value = sectionName });
        command.Parameters.Add(new SqlParameter("@description",  SqlDbType.NVarChar, 255) { Value = (object?)description ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Section.Create", "ERRSEC99", new { SectionCode = sectionCode });
        return BuildResult("Section.Create", reader.GetString(1), new { SectionCode = sectionCode });
    }

    public OperationResult UpdateSection(string sectionCode, string? sectionName = null, string? description = null, bool clearDesc = false)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_update_section";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@section_code", SqlDbType.NVarChar, 50)  { Value = sectionCode });
        command.Parameters.Add(new SqlParameter("@section_name", SqlDbType.NVarChar, 100) { Value = (object?)sectionName  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@description",  SqlDbType.NVarChar, 255) { Value = (object?)description  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_desc",   SqlDbType.Bit)            { Value = clearDesc });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Section.Update", "ERRSEC99", new { SectionCode = sectionCode });
        return BuildResult("Section.Update", reader.GetString(1), new { SectionCode = sectionCode });
    }

    public OperationResult DeactivateSection(string sectionCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_deactivate_section";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@section_code", SqlDbType.NVarChar, 50) { Value = sectionCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Section.Deactivate", "ERRSEC99", new { SectionCode = sectionCode });
        return BuildResult("Section.Deactivate", reader.GetString(1), new { SectionCode = sectionCode });
    }

    public OperationResult ReactivateSection(string sectionCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_reactivate_section";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@section_code", SqlDbType.NVarChar, 50) { Value = sectionCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Section.Reactivate", "ERRSEC99", new { SectionCode = sectionCode });
        return BuildResult("Section.Reactivate", reader.GetString(1), new { SectionCode = sectionCode });
    }

    public OperationResult DeleteSection(string sectionCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_delete_section";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@section_code", SqlDbType.NVarChar, 50) { Value = sectionCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Section.Delete", "ERRSEC99", new { SectionCode = sectionCode });
        return BuildResult("Section.Delete", reader.GetString(1), new { SectionCode = sectionCode });
    }
}
