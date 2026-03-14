using Microsoft.Data.SqlClient;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlInventoryQueryRepository
{
    private readonly SqlConnectionFactory _connectionFactory;
    private readonly Guid _sessionId;
    private readonly int _userId;
    private readonly IErrorMessageResolver _errorResolver;

    public SqlInventoryQueryRepository(
        SqlConnectionFactory connectionFactory,
        Guid sessionId,
        int userId,
        IErrorMessageResolver errorResolver)
    {
        _connectionFactory = connectionFactory;
        _sessionId = sessionId;
        _userId = userId;
        _errorResolver = errorResolver;
    }

    public InventoryUnitDto? GetInventoryUnitByExternalRef(string externalRef)
    {
        using var conn = _connectionFactory.Create();

        using var cmd = new SqlCommand(@"
            SELECT inventory_unit_id, external_ref
            FROM inventory.inventory_units
            WHERE external_ref = @external_ref
        ", conn);

        cmd.Parameters.AddWithValue("@external_ref", externalRef);

        conn.Open();

        using var reader = cmd.ExecuteReader();

        if (!reader.Read())
            return null;

        return new InventoryUnitDto
        {
            InventoryUnitId = reader.GetInt32(0),
            ExternalRef = reader.GetString(1)
        };
    }

    public int GetUnitsAwaitingPutawayCount()
    {
        using var conn = _connectionFactory.Create();
        using var cmd = conn.CreateCommand();

        cmd.CommandText = "warehouse.usp_get_units_awaiting_putaway_count";
        cmd.CommandType = System.Data.CommandType.StoredProcedure;

        var result = cmd.ExecuteScalar();

        if (result == null || result == DBNull.Value)
            return 0;

        return Convert.ToInt32(result);
    }
}