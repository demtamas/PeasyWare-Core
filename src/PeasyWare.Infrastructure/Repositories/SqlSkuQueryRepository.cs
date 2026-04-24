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

    public SqlSkuQueryRepository(
        SqlConnectionFactory factory,
        SessionContext       session)
    {
        _factory = factory;
        _session = session;
    }

    public SkuDto? GetByCode(string skuCode)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT sku_id, sku_code, sku_description, ean,
                   uom_code, weight_per_unit, standard_hu_quantity,
                   is_hazardous, is_active
            FROM inventory.skus
            WHERE sku_code = @sku_code
        """;

        command.Parameters.AddWithValue("@sku_code", skuCode);

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return null;

        return new SkuDto
        {
            SkuId              = reader.GetInt32(reader.GetOrdinal("sku_id")),
            SkuCode            = reader.GetString(reader.GetOrdinal("sku_code")),
            SkuDescription     = reader.GetString(reader.GetOrdinal("sku_description")),
            Ean                = reader.IsDBNull(reader.GetOrdinal("ean"))                ? null  : reader.GetString(reader.GetOrdinal("ean")),
            UomCode            = reader.GetString(reader.GetOrdinal("uom_code")),
            WeightPerUnit      = reader.IsDBNull(reader.GetOrdinal("weight_per_unit"))    ? null  : reader.GetDecimal(reader.GetOrdinal("weight_per_unit")),
            StandardHuQuantity = reader.GetInt32(reader.GetOrdinal("standard_hu_quantity")),
            IsHazardous        = reader.GetBoolean(reader.GetOrdinal("is_hazardous")),
            IsActive           = reader.GetBoolean(reader.GetOrdinal("is_active"))
        };
    }
}
