using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlInventoryCommandRepository : RepositoryBase, IInventoryCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlInventoryCommandRepository(
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

    public OperationResult UpdateStockStatus(
        IEnumerable<string> ssccs,
        string              newStatusCode,
        string?             reason = null)
    {
        var ssccList = string.Join(",", ssccs);

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inventory.usp_update_stock_status";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@sscc_list",  SqlDbType.NVarChar, -1)  { Value = ssccList });
        command.Parameters.Add(new SqlParameter("@new_status", SqlDbType.VarChar,  2)   { Value = newStatusCode });
        command.Parameters.Add(new SqlParameter("@reason",     SqlDbType.NVarChar, 200) { Value = (object?)reason ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRINV99", "Unexpected error.");

        var success  = reader.GetBoolean(reader.GetOrdinal("success"));
        var code     = reader.GetString(reader.GetOrdinal("result_code"));
        var affected = reader.GetInt32(reader.GetOrdinal("affected_count"));

        return BuildResult("Inventory.StatusUpdate", code, new
        {
            Ssccs         = ssccs,
            NewStatusCode = newStatusCode,
            Reason        = reason,
            AffectedCount = affected
        });
    }
}
