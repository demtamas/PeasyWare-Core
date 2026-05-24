using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlMovementQueryRepository : IMovementQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlMovementQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public IReadOnlyList<MovementDto> GetMovements(
        string?   movementTypeFilter = null,
        string?   ssccFilter         = null,
        DateTime? fromDate           = null,
        DateTime? toDate             = null,
        int       top                = 500)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        var where = new List<string>();
        if (movementTypeFilter is not null) where.Add("movement_type = @movement_type");
        if (ssccFilter         is not null) where.Add("sscc LIKE @sscc");
        if (fromDate           is not null) where.Add("moved_at >= @from_date");
        if (toDate             is not null) where.Add("moved_at <  @to_date");

        command.CommandText = $"""
            SELECT TOP (@top)
                movement_id, moved_at, moved_by,
                sscc, sku_code, sku_description, moved_qty,
                from_bin, to_bin,
                from_state_code, to_state_code,
                from_status_code, to_status_code,
                movement_type, reference_type, reference_ref,
                is_reversal
            FROM inventory.v_movements
            {(where.Count > 0 ? "WHERE " + string.Join(" AND ", where) : "")}
            ORDER BY moved_at DESC
            """;

        command.Parameters.Add(new SqlParameter("@top", SqlDbType.Int) { Value = top });

        if (movementTypeFilter is not null)
            command.Parameters.Add(new SqlParameter("@movement_type", SqlDbType.NVarChar, 30) { Value = movementTypeFilter });
        if (ssccFilter is not null)
            command.Parameters.Add(new SqlParameter("@sscc", SqlDbType.NVarChar, 100) { Value = $"%{ssccFilter}%" });
        if (fromDate is not null)
            command.Parameters.Add(new SqlParameter("@from_date", SqlDbType.DateTime2) { Value = fromDate.Value });
        if (toDate is not null)
            command.Parameters.Add(new SqlParameter("@to_date", SqlDbType.DateTime2) { Value = toDate.Value.AddDays(1) });

        using var reader = command.ExecuteReader();
        var results = new List<MovementDto>();

        while (reader.Read())
        {
            results.Add(new MovementDto
            {
                MovementId     = reader.GetInt32(reader.GetOrdinal("movement_id")),
                MovedAt        = reader.GetDateTime(reader.GetOrdinal("moved_at")),
                MovedBy        = reader.GetString(reader.GetOrdinal("moved_by")),
                Sscc           = reader.GetString(reader.GetOrdinal("sscc")),
                SkuCode        = reader.GetString(reader.GetOrdinal("sku_code")),
                SkuDescription = reader.GetString(reader.GetOrdinal("sku_description")),
                MovedQty       = reader.GetInt32(reader.GetOrdinal("moved_qty")),
                FromBin        = reader.IsDBNull(reader.GetOrdinal("from_bin"))          ? null : reader.GetString(reader.GetOrdinal("from_bin")),
                ToBin          = reader.IsDBNull(reader.GetOrdinal("to_bin"))            ? null : reader.GetString(reader.GetOrdinal("to_bin")),
                FromState      = reader.IsDBNull(reader.GetOrdinal("from_state_code"))   ? null : reader.GetString(reader.GetOrdinal("from_state_code")),
                ToState        = reader.IsDBNull(reader.GetOrdinal("to_state_code"))     ? null : reader.GetString(reader.GetOrdinal("to_state_code")),
                FromStatus     = reader.IsDBNull(reader.GetOrdinal("from_status_code"))  ? null : reader.GetString(reader.GetOrdinal("from_status_code")),
                ToStatus       = reader.IsDBNull(reader.GetOrdinal("to_status_code"))    ? null : reader.GetString(reader.GetOrdinal("to_status_code")),
                MovementType   = reader.GetString(reader.GetOrdinal("movement_type")),
                ReferenceType  = reader.IsDBNull(reader.GetOrdinal("reference_type"))    ? null : reader.GetString(reader.GetOrdinal("reference_type")),
                ReferenceRef   = reader.IsDBNull(reader.GetOrdinal("reference_ref"))     ? null : reader.GetString(reader.GetOrdinal("reference_ref")),
                IsReversal     = reader.GetBoolean(reader.GetOrdinal("is_reversal"))
            });
        }

        return results;
    }
}
