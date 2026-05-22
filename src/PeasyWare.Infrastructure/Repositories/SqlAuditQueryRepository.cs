using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlAuditQueryRepository : IAuditQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlAuditQueryRepository(SqlConnectionFactory factory, SessionContext session)
    {
        _factory = factory;
        _session = session;
    }

    public IReadOnlyList<SkuChangeLogDto> GetSkuChanges(
        string?  skuCode = null,
        DateOnly? from   = null,
        DateOnly? to     = null,
        int top          = 200)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "audit.usp_get_sku_changes";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(new SqlParameter("@sku_code",  SqlDbType.NVarChar, 50) { Value = (object?)skuCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@from_date", SqlDbType.Date)         { Value = from.HasValue ? (object)from.Value.ToDateTime(TimeOnly.MinValue) : DBNull.Value });
        command.Parameters.Add(new SqlParameter("@to_date",   SqlDbType.Date)         { Value = to.HasValue   ? (object)to.Value.ToDateTime(TimeOnly.MinValue)   : DBNull.Value });
        command.Parameters.Add(new SqlParameter("@top",       SqlDbType.Int)          { Value = top });

        using var reader = command.ExecuteReader();
        var results = new List<SkuChangeLogDto>();

        while (reader.Read())
        {
            results.Add(new SkuChangeLogDto
            {
                TraceId         = reader.GetInt64(reader.GetOrdinal("trace_id")),
                OccurredAt      = reader.GetDateTime(reader.GetOrdinal("occurred_at")),
                Username        = reader.IsDBNull(reader.GetOrdinal("username"))    ? null : reader.GetString(reader.GetOrdinal("username")),
                ActionType      = reader.GetString(reader.GetOrdinal("action_type")),
                SkuCode         = reader.IsDBNull(reader.GetOrdinal("sku_code"))    ? null : reader.GetString(reader.GetOrdinal("sku_code")),
                DescBefore      = Str(reader, "desc_before"),
                EanBefore       = Str(reader, "ean_before"),
                UomBefore       = Str(reader, "uom_before"),
                WeightBefore    = Dec(reader, "weight_before"),
                HuQtyBefore     = Int(reader, "hu_qty_before"),
                BatchReqBefore  = Bit(reader, "batch_req_before"),
                FullHuReqBefore = Bit(reader, "full_hu_req_before"),
                HazardousBefore = Bit(reader, "hazardous_before"),
                ActiveBefore    = Bit(reader, "active_before"),
                StorageBefore   = Str(reader, "storage_before"),
                SectionBefore   = Str(reader, "section_before"),
                OwnerBefore     = Str(reader, "owner_before"),
                DescAfter       = Str(reader, "desc_after"),
                EanAfter        = Str(reader, "ean_after"),
                UomAfter        = Str(reader, "uom_after"),
                WeightAfter     = Dec(reader, "weight_after"),
                HuQtyAfter      = Int(reader, "hu_qty_after"),
                BatchReqAfter   = Bit(reader, "batch_req_after"),
                FullHuReqAfter  = Bit(reader, "full_hu_req_after"),
                HazardousAfter  = Bit(reader, "hazardous_after"),
                ActiveAfter     = Bit(reader, "active_after"),
                StorageAfter    = Str(reader, "storage_after"),
                SectionAfter    = Str(reader, "section_after"),
                OwnerAfter      = Str(reader, "owner_after"),
            });
        }

        return results;
    }

    private static string?  Str(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : r.GetString(r.GetOrdinal(col));
    private static decimal? Dec(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : r.GetDecimal(r.GetOrdinal(col));
    private static int?     Int(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : r.GetInt32(r.GetOrdinal(col));
    private static bool?    Bit(SqlDataReader r, string col) => r.IsDBNull(r.GetOrdinal(col)) ? null : r.GetBoolean(r.GetOrdinal(col));
}
