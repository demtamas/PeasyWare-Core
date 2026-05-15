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
        string?  ean                      = null,
        string   uomCode                  = "Each",
        decimal? weightPerUnit            = null,
        int      standardHuQuantity       = 0,
        bool     isHazardous              = false,
        bool     isBatchRequired          = false,
        bool     isFullHuRequired         = false,
        string?  preferredStorageTypeCode = null,
        string?  preferredSectionCode     = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inventory.usp_create_sku";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@sku_code",                       SqlDbType.NVarChar, 50)  { Value = skuCode });
        command.Parameters.Add(new SqlParameter("@sku_description",                SqlDbType.NVarChar, 200) { Value = skuDescription });
        command.Parameters.Add(new SqlParameter("@ean",                            SqlDbType.NVarChar, 50)  { Value = (object?)ean                      ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@uom_code",                       SqlDbType.NVarChar, 20)  { Value = uomCode });
        command.Parameters.Add(new SqlParameter("@weight_per_unit",                SqlDbType.Decimal)       { Value = (object?)weightPerUnit             ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@standard_hu_quantity",           SqlDbType.Int)           { Value = standardHuQuantity });
        command.Parameters.Add(new SqlParameter("@is_hazardous",                   SqlDbType.Bit)           { Value = isHazardous });
        command.Parameters.Add(new SqlParameter("@is_batch_required",              SqlDbType.Bit)           { Value = isBatchRequired });
        command.Parameters.Add(new SqlParameter("@is_full_hu_required",            SqlDbType.Bit)           { Value = isFullHuRequired });
        command.Parameters.Add(new SqlParameter("@preferred_storage_type_code",    SqlDbType.NVarChar, 50)  { Value = (object?)preferredStorageTypeCode  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@preferred_storage_section_code", SqlDbType.NVarChar, 50)  { Value = (object?)preferredSectionCode      ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRSKU99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var skuId   = success ? reader.GetInt32(reader.GetOrdinal("sku_id")) : 0;

        return BuildResult("Sku.Create", code, new { SkuCode = skuCode, SkuId = skuId });
    }

    public OperationResult UpdateSku(
        string   skuCode,
        string   skuDescription,
        string?  ean                      = null,
        string   uomCode                  = "Each",
        decimal? weightPerUnit            = null,
        int      standardHuQuantity       = 0,
        bool     isHazardous              = false,
        bool     isBatchRequired          = false,
        bool     isFullHuRequired         = false,
        bool     isActive                 = true,
        string?  preferredStorageTypeCode = null,
        string?  preferredSectionCode     = null)
    {
        // Fetch before-state for audit trail
        object? before = null;
        using (var readConn = _factory.CreateForCommand(_session))
        using (var readCmd  = readConn.CreateCommand())
        {
            readCmd.CommandText = """
                SELECT sku_description, ean, uom_code, weight_per_unit,
                       standard_hu_quantity, is_hazardous, is_batch_required,
                       is_full_hu_required, is_active,
                       preferred_storage_type_code, preferred_section_code
                FROM inventory.v_skus
                WHERE sku_code = @sku_code
                """;
            readCmd.Parameters.AddWithValue("@sku_code", skuCode);
            using var r = readCmd.ExecuteReader();
            if (r.Read())
                before = new
                {
                    SkuDescription     = r.IsDBNull(0) ? null : r.GetString(0),
                    Ean                = r.IsDBNull(1) ? null : r.GetString(1),
                    UomCode            = r.IsDBNull(2) ? null : r.GetString(2),
                    WeightPerUnit      = r.IsDBNull(3) ? null : (decimal?)r.GetDecimal(3),
                    StandardHuQuantity = r.GetInt32(4),
                    IsHazardous        = r.GetBoolean(5),
                    IsBatchRequired    = r.GetBoolean(6),
                    IsFullHuRequired   = r.GetBoolean(7),
                    IsActive           = r.GetBoolean(8),
                    StorageTypeCode    = r.IsDBNull(9)  ? null : r.GetString(9),
                    SectionCode        = r.IsDBNull(10) ? null : r.GetString(10)
                };
        }

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inventory.usp_update_sku";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@sku_code",                       SqlDbType.NVarChar, 50)  { Value = skuCode });
        command.Parameters.Add(new SqlParameter("@sku_description",                SqlDbType.NVarChar, 200) { Value = skuDescription });
        command.Parameters.Add(new SqlParameter("@ean",                            SqlDbType.NVarChar, 50)  { Value = (object?)ean                      ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@uom_code",                       SqlDbType.NVarChar, 20)  { Value = uomCode });
        command.Parameters.Add(new SqlParameter("@weight_per_unit",                SqlDbType.Decimal)       { Value = (object?)weightPerUnit             ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@standard_hu_quantity",           SqlDbType.Int)           { Value = standardHuQuantity });
        command.Parameters.Add(new SqlParameter("@is_hazardous",                   SqlDbType.Bit)           { Value = isHazardous });
        command.Parameters.Add(new SqlParameter("@is_batch_required",              SqlDbType.Bit)           { Value = isBatchRequired });
        command.Parameters.Add(new SqlParameter("@is_full_hu_required",            SqlDbType.Bit)           { Value = isFullHuRequired });
        command.Parameters.Add(new SqlParameter("@is_active",                      SqlDbType.Bit)           { Value = isActive });
        command.Parameters.Add(new SqlParameter("@preferred_storage_type_code",    SqlDbType.NVarChar, 50)  { Value = (object?)preferredStorageTypeCode  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@preferred_storage_section_code", SqlDbType.NVarChar, 50)  { Value = (object?)preferredSectionCode      ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRSKU99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        var after = new
        {
            SkuDescription     = skuDescription,
            Ean                = ean,
            UomCode            = uomCode,
            WeightPerUnit      = weightPerUnit,
            StandardHuQuantity = standardHuQuantity,
            IsHazardous        = isHazardous,
            IsBatchRequired    = isBatchRequired,
            IsFullHuRequired   = isFullHuRequired,
            IsActive           = isActive,
            StorageTypeCode    = preferredStorageTypeCode,
            SectionCode        = preferredSectionCode
        };

        return BuildResult("Sku.Update", code, new { SkuCode = skuCode, Before = before, After = after });
    }
}
