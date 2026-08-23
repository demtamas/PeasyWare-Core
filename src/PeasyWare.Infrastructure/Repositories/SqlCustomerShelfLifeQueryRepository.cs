using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlCustomerShelfLifeQueryRepository : ICustomerShelfLifeQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlCustomerShelfLifeQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public IReadOnlyList<CustomerShelfLifeRequirementDto> GetAll()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT customer_party_id, customer_party_code, customer_name,
                   sku_id, sku_code, sku_description,
                   minimum_remaining_shelf_life_days,
                   created_at, created_by_username,
                   updated_at, updated_by_username
            FROM inventory.v_customer_shelf_life_requirements
            ORDER BY customer_name, sku_code
            """;

        using var reader = command.ExecuteReader();
        var results = new List<CustomerShelfLifeRequirementDto>();

        while (reader.Read())
        {
            results.Add(new CustomerShelfLifeRequirementDto
            {
                CustomerPartyId               = reader.GetInt32(reader.GetOrdinal("customer_party_id")),
                CustomerPartyCode             = reader.GetString(reader.GetOrdinal("customer_party_code")),
                CustomerName                  = reader.GetString(reader.GetOrdinal("customer_name")),
                SkuId                         = reader.GetInt32(reader.GetOrdinal("sku_id")),
                SkuCode                       = reader.GetString(reader.GetOrdinal("sku_code")),
                SkuDescription                = reader.GetString(reader.GetOrdinal("sku_description")),
                MinimumRemainingShelfLifeDays = reader.GetInt32(reader.GetOrdinal("minimum_remaining_shelf_life_days")),
                CreatedAt                     = reader.GetDateTime(reader.GetOrdinal("created_at")),
                CreatedByUsername             = reader.IsDBNull(reader.GetOrdinal("created_by_username")) ? null : reader.GetString(reader.GetOrdinal("created_by_username")),
                UpdatedAt                     = reader.IsDBNull(reader.GetOrdinal("updated_at"))           ? null : reader.GetDateTime(reader.GetOrdinal("updated_at")),
                UpdatedByUsername             = reader.IsDBNull(reader.GetOrdinal("updated_by_username"))  ? null : reader.GetString(reader.GetOrdinal("updated_by_username"))
            });
        }

        return results;
    }
}
