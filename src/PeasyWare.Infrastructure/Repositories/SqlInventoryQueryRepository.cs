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
    // Excludes terminal states (REV, SHP) — same rule as the unique index.
    // Parameter size matches the column definition (NVARCHAR(100)).
    // --------------------------------------------------

    public InventoryUnitDto? GetInventoryUnitByExternalRef(string externalRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT inventory_unit_id, external_ref
            FROM inventory.inventory_units
            WHERE external_ref      = @external_ref
              AND stock_state_code NOT IN ('REV', 'SHP')
        """;

        command.Parameters.Add(
            new SqlParameter("@external_ref", SqlDbType.NVarChar, 100)
            {
                Value = externalRef.Trim()
            });

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            return null;

        var colUnitId      = reader.GetOrdinal("inventory_unit_id");
        var colExternalRef = reader.GetOrdinal("external_ref");

        return new InventoryUnitDto
        {
            InventoryUnitId = reader.GetInt32(colUnitId),
            ExternalRef     = reader.GetString(colExternalRef)
        };
    }

    // --------------------------------------------------
    // Units awaiting putaway count
    // --------------------------------------------------

    public int GetUnitsAwaitingPutawayCount()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT COUNT(*)
            FROM inventory.v_units_awaiting_putaway
        """;

        var result = command.ExecuteScalar();

        if (result == null || result == DBNull.Value)
            return 0;

        return Convert.ToInt32(result);
    }
}
