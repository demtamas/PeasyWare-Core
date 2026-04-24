using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlSkuCommandRepository : RepositoryBase, ISkuCommandRepository
{
    private readonly SqlConnectionFactory  _factory;
    private readonly SessionContext        _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;

    public SqlSkuCommandRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory  = factory;
        _session  = session;
        _resolver = resolver;
        _logger   = logger;
    }

    public OperationResult CreateSku(
        string   skuCode,
        string   skuDescription,
        string?  ean                = null,
        string   uomCode            = "Each",
        decimal? weightPerUnit      = null,
        int      standardHuQuantity = 0,
        bool     isHazardous        = false)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inventory.usp_create_sku";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@sku_code",             SqlDbType.NVarChar, 50)  { Value = skuCode });
        command.Parameters.Add(new SqlParameter("@sku_description",      SqlDbType.NVarChar, 200) { Value = skuDescription });
        command.Parameters.Add(new SqlParameter("@ean",                  SqlDbType.NVarChar, 50)  { Value = (object?)ean             ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@uom_code",             SqlDbType.NVarChar, 20)  { Value = uomCode });
        command.Parameters.Add(new SqlParameter("@weight_per_unit",      SqlDbType.Decimal)       { Value = (object?)weightPerUnit   ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@standard_hu_quantity", SqlDbType.Int)           { Value = standardHuQuantity });
        command.Parameters.Add(new SqlParameter("@is_hazardous",         SqlDbType.Bit)           { Value = isHazardous });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRSKU99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var skuId   = success ? reader.GetInt32(reader.GetOrdinal("sku_id")) : 0;

        return BuildResult("Sku.Create", code, new { SkuCode = skuCode, SkuId = skuId });
    }
}
