using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlLocationQueryRepository : ILocationQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlLocationQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public IReadOnlyList<LocationDto> GetLocations(
        bool    withStockOnly    = true,
        string? storageTypeCode  = null,
        string? zoneCode         = null,
        string? search           = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        var where = new List<string> { "is_active = 1" };

        if (withStockOnly)        where.Add("unit_count > 0");
        if (storageTypeCode != null) where.Add("storage_type_code = @type_code");
        if (zoneCode        != null) where.Add("zone_code = @zone_code");
        if (search          != null) where.Add("(bin_code LIKE @search OR sku_code LIKE @search OR sscc LIKE @search)");

        command.CommandText = $"""
            SELECT
                bin_id, bin_code, storage_type_code, storage_type_name,
                section_code, zone_code, zone_name,
                capacity, is_active, is_locked, locked_reason, locked_by_username, locked_at, notes,
                unit_count, total_qty,
                sscc, sku_code, sku_description, batch_number, best_before_date,
                stock_state, stock_status
            FROM locations.v_locations
            WHERE {string.Join(" AND ", where)}
            ORDER BY bin_code
            """;

        if (storageTypeCode != null)
            command.Parameters.Add(new SqlParameter("@type_code", SqlDbType.NVarChar, 50) { Value = storageTypeCode });
        if (zoneCode != null)
            command.Parameters.Add(new SqlParameter("@zone_code", SqlDbType.NVarChar, 50) { Value = zoneCode });
        if (search != null)
            command.Parameters.Add(new SqlParameter("@search", SqlDbType.NVarChar, 100) { Value = $"%{search}%" });

        using var reader = command.ExecuteReader();
        var results = new List<LocationDto>();

        while (reader.Read())
        {
            results.Add(new LocationDto
            {
                BinId            = reader.GetInt32(reader.GetOrdinal("bin_id")),
                BinCode          = reader.GetString(reader.GetOrdinal("bin_code")),
                StorageTypeCode  = reader.GetString(reader.GetOrdinal("storage_type_code")),
                StorageTypeName  = Str(reader, "storage_type_name"),
                SectionCode      = Str(reader, "section_code"),
                ZoneCode         = Str(reader, "zone_code"),
                ZoneName         = Str(reader, "zone_name"),
                Capacity         = reader.GetInt32(reader.GetOrdinal("capacity")),
                IsActive         = reader.GetBoolean(reader.GetOrdinal("is_active")),
                IsLocked         = reader.GetBoolean(reader.GetOrdinal("is_locked")),
                LockedReason     = Str(reader, "locked_reason"),
                LockedByUsername = Str(reader, "locked_by_username"),
                LockedAt         = reader.IsDBNull(reader.GetOrdinal("locked_at")) ? null : reader.GetDateTime(reader.GetOrdinal("locked_at")),
                Notes            = Str(reader, "notes"),
                UnitCount        = reader.GetInt32(reader.GetOrdinal("unit_count")),
                TotalQty         = reader.GetInt32(reader.GetOrdinal("total_qty")),
                Sscc             = Str(reader, "sscc"),
                SkuCode          = Str(reader, "sku_code"),
                SkuDescription   = Str(reader, "sku_description"),
                BatchNumber      = Str(reader, "batch_number"),
                BestBeforeDate   = reader.IsDBNull(reader.GetOrdinal("best_before_date")) ? null : reader.GetDateTime(reader.GetOrdinal("best_before_date")),
                StockState       = Str(reader, "stock_state"),
                StockStatus      = Str(reader, "stock_status")
            });
        }

        return results;
    }

    public IReadOnlyList<string> GetStorageTypeCodes()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "SELECT DISTINCT storage_type_code FROM locations.storage_types WHERE is_active = 1 ORDER BY storage_type_code";
        using var reader     = command.ExecuteReader();
        var results          = new List<string>();
        while (reader.Read()) results.Add(reader.GetString(0));
        return results;
    }

    public IReadOnlyList<string> GetZoneCodes()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();
        command.CommandText  = "SELECT DISTINCT zone_code FROM locations.zones WHERE is_active = 1 ORDER BY zone_code";
        using var reader     = command.ExecuteReader();
        var results          = new List<string>();
        while (reader.Read()) results.Add(reader.GetString(0));
        return results;
    }

    private static string? Str(SqlDataReader r, string col) =>
        r.IsDBNull(r.GetOrdinal(col)) ? null : r.GetString(r.GetOrdinal(col));
}
