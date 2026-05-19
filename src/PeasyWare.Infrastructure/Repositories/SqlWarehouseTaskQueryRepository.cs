using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlWarehouseTaskQueryRepository
    : RepositoryBase, IWarehouseTaskQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext       _session;

    public SqlWarehouseTaskQueryRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
    }

    public IEnumerable<WarehouseTaskDto> GetTasks(bool activeOnly = true)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = activeOnly
            ? """
                SELECT * FROM warehouse.v_warehouse_tasks
                WHERE is_terminal = 0
                ORDER BY created_at DESC
              """
            : """
                SELECT * FROM warehouse.v_warehouse_tasks
                ORDER BY created_at DESC
              """;

        command.CommandType = CommandType.Text;

        using var reader = command.ExecuteReader();
        var results = new List<WarehouseTaskDto>();
        while (reader.Read())
            results.Add(ReadRow(reader));
        return results;
    }

    public IEnumerable<WarehouseTaskDto> GetTasksByUnit(string sscc)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = """
            SELECT * FROM warehouse.v_warehouse_tasks
            WHERE sscc = @sscc COLLATE Latin1_General_CS_AS
            ORDER BY created_at DESC
        """;

        command.CommandType = CommandType.Text;
        command.Parameters.Add(new SqlParameter("@sscc", SqlDbType.NVarChar, 100) { Value = sscc });

        using var reader = command.ExecuteReader();
        var results = new List<WarehouseTaskDto>();
        while (reader.Read())
            results.Add(ReadRow(reader));
        return results;
    }

    private static WarehouseTaskDto ReadRow(SqlDataReader r) => new()
    {
        TaskId         = r.GetInt32(r.GetOrdinal("task_id")),
        TaskTypeCode   = r.GetString(r.GetOrdinal("task_type_code")),
        TaskState      = r.GetString(r.GetOrdinal("task_state")),
        TaskStateCode  = r.GetString(r.GetOrdinal("task_state_code")),
        IsTerminal     = r.GetBoolean(r.GetOrdinal("is_terminal")),
        Sscc           = r.GetString(r.GetOrdinal("sscc")),
        SkuCode        = r.GetString(r.GetOrdinal("sku_code")),
        SkuDescription = r.GetString(r.GetOrdinal("sku_description")),
        Quantity       = r.GetInt32(r.GetOrdinal("quantity")),
        BatchNumber    = r.IsDBNull(r.GetOrdinal("batch_number"))    ? null : r.GetString(r.GetOrdinal("batch_number")),
        SourceBin      = r.IsDBNull(r.GetOrdinal("source_bin"))      ? null : r.GetString(r.GetOrdinal("source_bin")),
        DestinationBin = r.IsDBNull(r.GetOrdinal("destination_bin")) ? null : r.GetString(r.GetOrdinal("destination_bin")),
        ClaimedBy      = r.IsDBNull(r.GetOrdinal("claimed_by"))      ? null : r.GetString(r.GetOrdinal("claimed_by")),
        ClaimedAt      = r.IsDBNull(r.GetOrdinal("claimed_at"))      ? null : r.GetDateTime(r.GetOrdinal("claimed_at")),
        ExpiresAt      = r.IsDBNull(r.GetOrdinal("expires_at"))      ? null : r.GetDateTime(r.GetOrdinal("expires_at")),
        CompletedBy    = r.IsDBNull(r.GetOrdinal("completed_by"))    ? null : r.GetString(r.GetOrdinal("completed_by")),
        CompletedAt    = r.IsDBNull(r.GetOrdinal("completed_at"))    ? null : r.GetDateTime(r.GetOrdinal("completed_at")),
        CreatedBy      = r.IsDBNull(r.GetOrdinal("created_by"))      ? null : r.GetString(r.GetOrdinal("created_by")),
        CreatedAt      = r.GetDateTime(r.GetOrdinal("created_at")),
        UpdatedAt      = r.IsDBNull(r.GetOrdinal("updated_at"))      ? null : r.GetDateTime(r.GetOrdinal("updated_at")),
    };
}
