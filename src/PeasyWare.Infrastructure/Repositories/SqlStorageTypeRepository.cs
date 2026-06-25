using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlStorageTypeRepository : RepositoryBase, IStorageTypeRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlStorageTypeRepository(
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

    public IReadOnlyList<StorageTypeDto> GetStorageTypes(bool includeInactive = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = $"""
            SELECT storage_type_id, storage_type_code, storage_type_name, description, is_active,
                   created_at, created_by_username, updated_at, updated_by_username,
                   total_bins, active_bins
            FROM locations.v_storage_types
            {(includeInactive ? "" : "WHERE is_active = 1")}
            ORDER BY storage_type_code
            """;

        using var reader = command.ExecuteReader();
        var results = new List<StorageTypeDto>();
        while (reader.Read())
        {
            results.Add(new StorageTypeDto
            {
                StorageTypeId     = reader.GetInt32(0),
                StorageTypeCode   = reader.GetString(1),
                StorageTypeName   = reader.GetString(2),
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

    public OperationResult CreateStorageType(string storageTypeCode, string storageTypeName, string? description = null)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_create_storage_type";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50)  { Value = storageTypeCode });
        command.Parameters.Add(new SqlParameter("@storage_type_name", SqlDbType.NVarChar, 100) { Value = storageTypeName });
        command.Parameters.Add(new SqlParameter("@description",       SqlDbType.NVarChar, 255) { Value = (object?)description ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("StorageType.Create", "ERRTYP99", new { StorageTypeCode = storageTypeCode });
        return BuildResult("StorageType.Create", reader.GetString(1), new { StorageTypeCode = storageTypeCode });
    }

    public OperationResult UpdateStorageType(string storageTypeCode, string? storageTypeName = null, string? description = null, bool clearDesc = false)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_update_storage_type";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50)  { Value = storageTypeCode });
        command.Parameters.Add(new SqlParameter("@storage_type_name", SqlDbType.NVarChar, 100) { Value = (object?)storageTypeName ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@description",       SqlDbType.NVarChar, 255) { Value = (object?)description     ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@clear_desc",        SqlDbType.Bit)            { Value = clearDesc });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("StorageType.Update", "ERRTYP99", new { StorageTypeCode = storageTypeCode });
        return BuildResult("StorageType.Update", reader.GetString(1), new { StorageTypeCode = storageTypeCode });
    }

    public OperationResult DeactivateStorageType(string storageTypeCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_deactivate_storage_type";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50) { Value = storageTypeCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("StorageType.Deactivate", "ERRTYP99", new { StorageTypeCode = storageTypeCode });
        return BuildResult("StorageType.Deactivate", reader.GetString(1), new { StorageTypeCode = storageTypeCode });
    }

    public OperationResult ReactivateStorageType(string storageTypeCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_reactivate_storage_type";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50) { Value = storageTypeCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("StorageType.Reactivate", "ERRTYP99", new { StorageTypeCode = storageTypeCode });
        return BuildResult("StorageType.Reactivate", reader.GetString(1), new { StorageTypeCode = storageTypeCode });
    }

    public OperationResult DeleteStorageType(string storageTypeCode)
    {
        EnsureSession();
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "locations.usp_delete_storage_type";
        command.CommandType  = CommandType.StoredProcedure;
        command.Parameters.Add(new SqlParameter("@storage_type_code", SqlDbType.NVarChar, 50) { Value = storageTypeCode });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("StorageType.Delete", "ERRTYP99", new { StorageTypeCode = storageTypeCode });
        return BuildResult("StorageType.Delete", reader.GetString(1), new { StorageTypeCode = storageTypeCode });
    }
}
