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
    private readonly SessionContext       _session;

    public SqlInventoryQueryRepository(
        SqlConnectionFactory factory,
        SessionContext       session)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    // --------------------------------------------------
    // Inventory by external ref (SSCC / HU)
    // Excludes terminal states (REV, SHP).
    // --------------------------------------------------

    public InventoryUnitDto? GetInventoryUnitByExternalRef(string externalRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

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

        return new InventoryUnitDto
        {
            InventoryUnitId = reader.GetInt32(reader.GetOrdinal("inventory_unit_id")),
            ExternalRef     = reader.GetString(reader.GetOrdinal("external_ref"))
        };
    }

    // --------------------------------------------------
    // Units awaiting putaway count
    // --------------------------------------------------

    public int GetUnitsAwaitingPutawayCount()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT COUNT(*)
            FROM inventory.v_units_awaiting_putaway
        """;

        var result = command.ExecuteScalar();

        return result == null || result == DBNull.Value
            ? 0
            : Convert.ToInt32(result);
    }

    // --------------------------------------------------
    // SSCC query — reads from v_active_inventory
    // Returns null if SSCC not found or is in a terminal state.
    // --------------------------------------------------

    public ActiveInventoryDto? GetActiveInventoryBySscc(string sscc)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT
                sscc,
                sku_code,
                sku_description,
                batch_number,
                best_before_date,
                quantity,
                stock_state,
                stock_status,
                bin_code,
                zone_code,
                storage_type_code,
                received_at,
                received_by,
                last_movement_type,
                last_movement_at,
                last_moved_by
            FROM inventory.v_active_inventory
            WHERE sscc = @sscc
        """;

        command.Parameters.Add(
            new SqlParameter("@sscc", SqlDbType.NVarChar, 100)
            {
                Value = sscc.Trim()
            });

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            return null;

        var colSscc        = reader.GetOrdinal("sscc");
        var colSkuCode     = reader.GetOrdinal("sku_code");
        var colSkuDesc     = reader.GetOrdinal("sku_description");
        var colBatch       = reader.GetOrdinal("batch_number");
        var colBbe         = reader.GetOrdinal("best_before_date");
        var colQty         = reader.GetOrdinal("quantity");
        var colState       = reader.GetOrdinal("stock_state");
        var colStatus      = reader.GetOrdinal("stock_status");
        var colBin         = reader.GetOrdinal("bin_code");
        var colZone        = reader.GetOrdinal("zone_code");
        var colStorageType = reader.GetOrdinal("storage_type_code");
        var colReceivedAt  = reader.GetOrdinal("received_at");
        var colReceivedBy  = reader.GetOrdinal("received_by");
        var colLastMvType  = reader.GetOrdinal("last_movement_type");
        var colLastMvAt    = reader.GetOrdinal("last_movement_at");
        var colLastMvBy    = reader.GetOrdinal("last_moved_by");

        return new ActiveInventoryDto
        {
            Sscc             = reader.GetString(colSscc),
            SkuCode          = reader.GetString(colSkuCode),
            SkuDescription   = reader.GetString(colSkuDesc),
            BatchNumber      = reader.IsDBNull(colBatch)   ? null : reader.GetString(colBatch),
            BestBeforeDate   = reader.IsDBNull(colBbe)     ? null
                               : DateOnly.FromDateTime(reader.GetDateTime(colBbe)),
            Quantity         = reader.GetInt32(colQty),
            StockState       = reader.GetString(colState),
            StockStatus      = reader.GetString(colStatus),
            BinCode          = reader.GetString(colBin),
            ZoneCode         = reader.IsDBNull(colZone)        ? null : reader.GetString(colZone),
            StorageTypeCode  = reader.IsDBNull(colStorageType) ? null : reader.GetString(colStorageType),
            ReceivedAt       = reader.GetDateTime(colReceivedAt),
            ReceivedBy       = reader.IsDBNull(colReceivedBy)  ? null : reader.GetString(colReceivedBy),
            LastMovementType = reader.IsDBNull(colLastMvType)  ? null : reader.GetString(colLastMvType),
            LastMovementAt   = reader.IsDBNull(colLastMvAt)    ? null : reader.GetDateTime(colLastMvAt),
            LastMovedBy      = reader.IsDBNull(colLastMvBy)    ? null : reader.GetString(colLastMvBy)
        };
    }
}
