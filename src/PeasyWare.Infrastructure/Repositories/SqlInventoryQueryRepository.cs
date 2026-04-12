using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// QUERY repository for inventory.
/// Read-only, uses SessionContext for DB tracing.
/// </summary>
public sealed class SqlInventoryQueryRepository : IInventoryQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;

    public SqlInventoryQueryRepository(
        SqlConnectionFactory factory,
        SessionContext session)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    // --------------------------------------------------
    // Inventory by external ref (SSCC / HU)
    // --------------------------------------------------

    public InventoryUnitDto? GetInventoryUnitByExternalRef(string externalRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT inventory_unit_id, external_ref
            FROM inventory.inventory_units
            WHERE external_ref = @external_ref
        """;

        command.Parameters.Add(
            new SqlParameter("@external_ref", SqlDbType.NVarChar, 50)
            {
                Value = externalRef
            });

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            return null;

        return new InventoryUnitDto
        {
            InventoryUnitId = reader.GetInt32(0),
            ExternalRef = reader.GetString(1)
        };
    }

    // --------------------------------------------------
    // Units awaiting putaway
    // --------------------------------------------------

    public int GetUnitsAwaitingPutawayCount()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "warehouse.usp_get_units_awaiting_putaway_count";
        command.CommandType = CommandType.StoredProcedure;

        var result = command.ExecuteScalar();

        if (result == null || result == DBNull.Value)
            return 0;

        return Convert.ToInt32(result);
    }
}