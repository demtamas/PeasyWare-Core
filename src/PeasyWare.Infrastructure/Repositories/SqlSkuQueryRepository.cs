using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlSkuQueryRepository : ISkuQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    private const string SelectCols = """
        SELECT sku_id, sku_code, sku_description, ean, uom_code,
               weight_per_unit, standard_hu_quantity, is_hazardous,
               is_batch_required, is_full_hu_required, is_active,
               preferred_storage_type_code, preferred_section_code,
               owner_party_code, owner_name,
               created_at, created_by_username,
               updated_at, updated_by_username
        FROM inventory.v_skus
        """;

    public SqlSkuQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public SkuDto? GetByCode(string skuCode)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = SelectCols + " WHERE sku_code = @sku_code";
        command.Parameters.AddWithValue("@sku_code", skuCode);

        using var reader = command.ExecuteReader();
        return reader.Read() ? ReadRow(reader) : null;
    }

    public IReadOnlyList<SkuDto> GetAll(bool includeInactive = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = includeInactive
            ? SelectCols + " ORDER BY sku_code"
            : SelectCols + " WHERE is_active = 1 ORDER BY sku_code";

        using var reader = command.ExecuteReader();
        var results = new List<SkuDto>();

        while (reader.Read())
            results.Add(ReadRow(reader));

        return results;
    }

    private static SkuDto ReadRow(SqlDataReader r) => new()
    {
        SkuId                    = r.GetInt32(r.GetOrdinal("sku_id")),
        SkuCode                  = r.GetString(r.GetOrdinal("sku_code")),
        SkuDescription           = r.GetString(r.GetOrdinal("sku_description")),
        Ean                      = r.IsDBNull(r.GetOrdinal("ean"))                       ? null : r.GetString(r.GetOrdinal("ean")),
        UomCode                  = r.GetString(r.GetOrdinal("uom_code")),
        WeightPerUnit            = r.IsDBNull(r.GetOrdinal("weight_per_unit"))           ? null : r.GetDecimal(r.GetOrdinal("weight_per_unit")),
        StandardHuQuantity       = r.GetInt32(r.GetOrdinal("standard_hu_quantity")),
        IsHazardous              = r.GetBoolean(r.GetOrdinal("is_hazardous")),
        IsBatchRequired          = r.GetBoolean(r.GetOrdinal("is_batch_required")),
        IsFullHuRequired         = r.GetBoolean(r.GetOrdinal("is_full_hu_required")),
        IsActive                 = r.GetBoolean(r.GetOrdinal("is_active")),
        PreferredStorageTypeCode = r.IsDBNull(r.GetOrdinal("preferred_storage_type_code")) ? null : r.GetString(r.GetOrdinal("preferred_storage_type_code")),
        PreferredSectionCode     = r.IsDBNull(r.GetOrdinal("preferred_section_code"))      ? null : r.GetString(r.GetOrdinal("preferred_section_code")),
        OwnerPartyCode           = r.IsDBNull(r.GetOrdinal("owner_party_code"))            ? null : r.GetString(r.GetOrdinal("owner_party_code")),
        OwnerName                = r.IsDBNull(r.GetOrdinal("owner_name"))                  ? null : r.GetString(r.GetOrdinal("owner_name")),
        CreatedAt                = r.IsDBNull(r.GetOrdinal("created_at"))               ? null : r.GetDateTime(r.GetOrdinal("created_at")),
        CreatedByUsername        = r.IsDBNull(r.GetOrdinal("created_by_username"))      ? null : r.GetString(r.GetOrdinal("created_by_username")),
        UpdatedAt                = r.IsDBNull(r.GetOrdinal("updated_at"))               ? null : r.GetDateTime(r.GetOrdinal("updated_at")),
        UpdatedByUsername        = r.IsDBNull(r.GetOrdinal("updated_by_username"))      ? null : r.GetString(r.GetOrdinal("updated_by_username")),
    };
}
