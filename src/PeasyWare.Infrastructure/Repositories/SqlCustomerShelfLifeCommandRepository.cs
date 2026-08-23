using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlCustomerShelfLifeCommandRepository : RepositoryBase, ICustomerShelfLifeCommandRepository
{
    private readonly SqlConnectionFactory  _factory;
    private readonly SessionContext        _session;

    public SqlCustomerShelfLifeCommandRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory = factory;
        _session = session;
    }

    public OperationResult SetRequirement(string customerPartyCode, string skuCode, int minimumRemainingShelfLifeDays)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inventory.usp_set_customer_shelf_life_requirement";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@customer_party_code",               SqlDbType.NVarChar, 50) { Value = customerPartyCode });
        command.Parameters.Add(new SqlParameter("@sku_code",                          SqlDbType.NVarChar, 50) { Value = skuCode });
        command.Parameters.Add(new SqlParameter("@minimum_remaining_shelf_life_days",  SqlDbType.Int)          { Value = minimumRemainingShelfLifeDays });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRCSL99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Inventory.SetCustomerShelfLifeRequirement", code,
            new { CustomerPartyCode = customerPartyCode, SkuCode = skuCode, MinimumRemainingShelfLifeDays = minimumRemainingShelfLifeDays });
    }

    public OperationResult DeleteRequirement(string customerPartyCode, string skuCode)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inventory.usp_delete_customer_shelf_life_requirement";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@customer_party_code", SqlDbType.NVarChar, 50) { Value = customerPartyCode });
        command.Parameters.Add(new SqlParameter("@sku_code",            SqlDbType.NVarChar, 50) { Value = skuCode });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRCSL99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Inventory.DeleteCustomerShelfLifeRequirement", code,
            new { CustomerPartyCode = customerPartyCode, SkuCode = skuCode });
    }
}
