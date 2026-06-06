using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlLocationCommandRepository : RepositoryBase, ILocationCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlLocationCommandRepository(
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

    public OperationResult LockBin(string binCode, string? reason = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_lock_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code", SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.Add(new SqlParameter("@reason",   SqlDbType.NVarChar, 255) { Value = (object?)reason ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Lock", "ERRBIN99", new { BinCode = binCode });
        return BuildResult("Location.Lock", reader.GetString(reader.GetOrdinal("result_code")), new { BinCode = binCode });
    }

    public OperationResult UnlockBin(string binCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_unlock_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code", SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Unlock", "ERRBIN99", new { BinCode = binCode });
        return BuildResult("Location.Unlock", reader.GetString(reader.GetOrdinal("result_code")), new { BinCode = binCode });
    }

    public OperationResult CreateBin(
        string  binCode,
        string  storageTypeCode,
        string? zoneCode    = null,
        string? sectionCode = null,
        int     capacity    = 1,
        string? notes       = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_create_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code",          SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50)  { Value = storageTypeCode });
        command.Parameters.Add(new SqlParameter("@zone_code",         SqlDbType.NVarChar, 50)  { Value = (object?)zoneCode    ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@section_code",      SqlDbType.NVarChar, 50)  { Value = (object?)sectionCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@capacity",          SqlDbType.Int)            { Value = capacity });
        command.Parameters.Add(new SqlParameter("@notes",             SqlDbType.NVarChar, 255) { Value = (object?)notes       ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Create", "ERRBIN99", new { BinCode = binCode });
        var code  = reader.GetString(reader.GetOrdinal("result_code"));
        var binId = reader.GetInt32(reader.GetOrdinal("bin_id"));
        return BuildResult("Location.Create", code, new { BinCode = binCode, BinId = binId });
    }

    public OperationResult CreateBinsBulk(
        string  prefix,
        string  storageTypeCode,
        int     rowFrom,
        int     rowTo,
        char    colFrom     = 'A',
        char    colTo       = 'A',
        int     depthFrom   = 1,
        int     depthTo     = 1,
        string? zoneCode    = null,
        string? sectionCode = null,
        int     capacity    = 1)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_create_bins_bulk";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@prefix",            SqlDbType.NVarChar, 10)  { Value = prefix });
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50)  { Value = storageTypeCode });
        command.Parameters.Add(new SqlParameter("@row_from",          SqlDbType.Int)            { Value = rowFrom });
        command.Parameters.Add(new SqlParameter("@row_to",            SqlDbType.Int)            { Value = rowTo });
        command.Parameters.Add(new SqlParameter("@col_from",          SqlDbType.Char, 1)        { Value = colFrom.ToString() });
        command.Parameters.Add(new SqlParameter("@col_to",            SqlDbType.Char, 1)        { Value = colTo.ToString() });
        command.Parameters.Add(new SqlParameter("@depth_from",        SqlDbType.Int)            { Value = depthFrom });
        command.Parameters.Add(new SqlParameter("@depth_to",          SqlDbType.Int)            { Value = depthTo });
        command.Parameters.Add(new SqlParameter("@zone_code",         SqlDbType.NVarChar, 50)  { Value = (object?)zoneCode    ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@section_code",      SqlDbType.NVarChar, 50)  { Value = (object?)sectionCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@capacity",          SqlDbType.Int)            { Value = capacity });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.CreateBulk", "ERRBIN99", new { Prefix = prefix });
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var created = reader.GetInt32(reader.GetOrdinal("created_count"));
        var skipped = reader.IsDBNull(reader.GetOrdinal("skipped_count")) ? 0 : reader.GetInt32(reader.GetOrdinal("skipped_count"));
        return BuildResult("Location.CreateBulk", code, new { Prefix = prefix, CreatedCount = created, SkippedCount = skipped });
    }

    public OperationResult UpdateBin(
        string  binCode,
        string? newBinCode      = null,
        string? storageTypeCode = null,
        string? zoneCode        = null,
        string? sectionCode     = null,
        int?    capacity        = null,
        string? notes           = null,
        bool    clearNotes      = false)
    {
        EnsureSession();

        // Fetch before-state for audit trail
        object? before = null;
        using (var rc = _factory.CreateForCommand(_session))
        using (var cmd = rc.CreateCommand())
        {
            cmd.CommandText = """
                SELECT bin_code, storage_type_code, section_code, zone_code,
                       capacity, is_active, is_locked, notes
                FROM locations.v_locations
                WHERE bin_code = @bin_code
                """;
            cmd.Parameters.AddWithValue("@bin_code", binCode);
            using var r = cmd.ExecuteReader();
            if (r.Read())
                before = new
                {
                    BinCode         = r.IsDBNull(0) ? null : r.GetString(0),
                    StorageTypeCode = r.IsDBNull(1) ? null : r.GetString(1),
                    SectionCode     = r.IsDBNull(2) ? null : r.GetString(2),
                    ZoneCode        = r.IsDBNull(3) ? null : r.GetString(3),
                    Capacity        = r.GetInt32(4),
                    IsActive        = r.GetBoolean(5),
                    IsLocked        = r.GetBoolean(6),
                    Notes           = r.IsDBNull(7) ? null : r.GetString(7)
                };
        }

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_update_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code_current",  SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.Add(new SqlParameter("@bin_code_new",      SqlDbType.NVarChar, 100) { Value = (object?)newBinCode      ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50)  { Value = (object?)storageTypeCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@zone_code",         SqlDbType.NVarChar, 50)  { Value = (object?)zoneCode         ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@section_code",      SqlDbType.NVarChar, 50)  { Value = (object?)sectionCode      ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@capacity",          SqlDbType.Int)            { Value = (object?)capacity         ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@notes",             SqlDbType.NVarChar, 255) { Value = (object?)notes            ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_notes",       SqlDbType.Bit)            { Value = clearNotes });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Update", "ERRBIN99", new { BinCode = binCode });

        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var capWarn = !reader.IsDBNull(reader.GetOrdinal("capacity_warning")) && reader.GetBoolean(reader.GetOrdinal("capacity_warning"));

        var after = new
        {
            BinCode         = newBinCode ?? binCode,
            StorageTypeCode = storageTypeCode,
            SectionCode     = sectionCode,
            ZoneCode        = zoneCode,
            Capacity        = capacity,
            Notes           = clearNotes ? null : notes
        };

        return BuildResult("Location.Update", code, new { BinCode = binCode, CapacityWarning = capWarn, Before = before, After = after });
    }

    public OperationResult DeleteBin(string binCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_delete_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code", SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Delete", "ERRBIN99", new { BinCode = binCode });
        return BuildResult("Location.Delete", reader.GetString(reader.GetOrdinal("result_code")), new { BinCode = binCode });
    }

    public OperationResult DeactivateBin(string binCode, string? reason = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_deactivate_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code", SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.Add(new SqlParameter("@reason",   SqlDbType.NVarChar, 255) { Value = (object?)reason ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Deactivate", "ERRBIN99", new { BinCode = binCode });
        return BuildResult("Location.Deactivate", reader.GetString(reader.GetOrdinal("result_code")), new { BinCode = binCode });
    }

    public OperationResult ReactivateBin(string binCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_reactivate_bin";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_code", SqlDbType.NVarChar, 100) { Value = binCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.Reactivate", "ERRBIN99", new { BinCode = binCode });
        return BuildResult("Location.Reactivate", reader.GetString(reader.GetOrdinal("result_code")), new { BinCode = binCode });
    }

    public OperationResult ActivateBins(IEnumerable<string> binCodes)
    {
        EnsureSession();

        var json = System.Text.Json.JsonSerializer.Serialize(binCodes);

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_activate_bins";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@bin_codes_json", SqlDbType.NVarChar, -1) { Value = json });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.ActivateBins", "ERRBIN99", new { Count = 0 });

        var code      = reader.GetString(reader.GetOrdinal("result_code"));
        var activated = reader.GetInt32(reader.GetOrdinal("activated_count"));
        var skipped   = reader.GetInt32(reader.GetOrdinal("skipped_count"));
        return BuildResult("Location.ActivateBins", code, new { ActivatedCount = activated, SkippedCount = skipped });
    }

    public OperationResult AssignBinsToSection(string sectionCode, IEnumerable<string> binCodes)
    {
        EnsureSession();
        var json = System.Text.Json.JsonSerializer.Serialize(binCodes);
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_assign_bins_to_section";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@section_code",    SqlDbType.NVarChar, 50)  { Value = sectionCode });
        command.Parameters.Add(new SqlParameter("@bin_codes_json",  SqlDbType.NVarChar, -1)  { Value = json });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.AssignSection", "ERRSEC99", new { SectionCode = sectionCode });
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var updated = reader.GetInt32(reader.GetOrdinal("updated_count"));
        return BuildResult("Location.AssignSection", code, new { SectionCode = sectionCode, UpdatedCount = updated });
    }

    public OperationResult AssignBinsToZone(string zoneCode, IEnumerable<string> binCodes)
    {
        EnsureSession();
        var json = System.Text.Json.JsonSerializer.Serialize(binCodes);
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_assign_bins_to_zone";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@zone_code",       SqlDbType.NVarChar, 50)  { Value = zoneCode });
        command.Parameters.Add(new SqlParameter("@bin_codes_json",  SqlDbType.NVarChar, -1)  { Value = json });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Location.AssignZone", "ERRZON99", new { ZoneCode = zoneCode });
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var updated = reader.GetInt32(reader.GetOrdinal("updated_count"));
        return BuildResult("Location.AssignZone", code, new { ZoneCode = zoneCode, UpdatedCount = updated });
    }
}
