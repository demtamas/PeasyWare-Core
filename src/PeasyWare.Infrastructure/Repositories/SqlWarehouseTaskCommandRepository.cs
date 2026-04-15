using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// Command repository for warehouse tasks.
/// </summary>
public sealed class SqlWarehouseTaskCommandRepository
    : RepositoryBase, IWarehouseTaskCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger _logger;

    public SqlWarehouseTaskCommandRepository(
        SqlConnectionFactory factory,
        SessionContext session,
        IErrorMessageResolver resolver,
        ILogger logger,
        SessionGuard sessionGuard)
        : base(sessionGuard, session.SessionId)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
        _resolver = resolver ?? throw new ArgumentNullException(nameof(resolver));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    // --------------------------------------------------------
    // Create Putaway Task
    // --------------------------------------------------------

    public PutawayTaskResult CreatePutawayTask(int inventoryUnitId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "warehouse.usp_putaway_create_task_for_unit";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@inventory_unit_id", SqlDbType.Int).Value = inventoryUnitId;
        command.Parameters.Add("@user_id", SqlDbType.Int).Value = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from putaway task creation.");

        // Resolve all ordinals by name — never by position
        var colSuccess         = reader.GetOrdinal("success");
        var colCode            = reader.GetOrdinal("result_code");
        var colTaskId          = reader.GetOrdinal("task_id");
        var colDestBin         = reader.GetOrdinal("destination_bin_code");
        var colUnitId          = reader.GetOrdinal("inventory_unit_id");
        var colSourceBin       = reader.GetOrdinal("source_bin_code");
        var colStockState      = reader.GetOrdinal("stock_state_code");
        var colStockStatus     = reader.GetOrdinal("stock_status_code");
        var colExpiresAt       = reader.GetOrdinal("expires_at");
        var colZone            = reader.GetOrdinal("zone_code");

        var success = reader.GetBoolean(colSuccess);
        var code    = reader.GetString(colCode);
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("WarehouseTask.Create", new
            {
                _session.UserId,
                _session.SessionId,
                InventoryUnitId = inventoryUnitId,
                ResultCode = code,
                Success = false
            });

            return new PutawayTaskResult
            {
                Success = false,
                ResultCode = code,
                FriendlyMessage = message
            };
        }

        var result = new PutawayTaskResult
        {
            Success            = true,
            ResultCode         = code,
            FriendlyMessage    = message,
            TaskId             = reader.GetInt32(colTaskId),
            DestinationBinCode = reader.GetString(colDestBin),
            InventoryUnitId    = reader.GetInt32(colUnitId),
            SourceBinCode      = reader.GetString(colSourceBin),
            StockStateCode     = reader.GetString(colStockState),
            StockStatusCode    = reader.GetString(colStockStatus),
            ExpiresAt          = reader.IsDBNull(colExpiresAt) ? null : reader.GetDateTime(colExpiresAt),
            ZoneCode           = reader.IsDBNull(colZone) ? null : reader.GetString(colZone)
        };

        _logger.Info("WarehouseTask.Create", new
        {
            _session.UserId,
            _session.SessionId,
            InventoryUnitId = inventoryUnitId,
            result.TaskId,
            result.DestinationBinCode,
            ResultCode = code,
            Success = true
        });

        return result;
    }

    // --------------------------------------------------------
    // Confirm Putaway Task
    // --------------------------------------------------------

    public OperationResult ConfirmPutawayTask(int taskId, string destination)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "warehouse.usp_putaway_confirm_task";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@task_id", SqlDbType.Int).Value = taskId;
        command.Parameters.Add("@scanned_bin_code", SqlDbType.NVarChar, 100).Value = destination;
        command.Parameters.Add("@user_id", SqlDbType.Int).Value = _session.UserId;
        command.Parameters.Add("@session_id", SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from putaway confirmation.");

        var colSuccess = reader.GetOrdinal("success");
        var colCode    = reader.GetOrdinal("result_code");

        var success = reader.GetBoolean(colSuccess);
        var code    = reader.GetString(colCode);
        var message = _resolver.Resolve(code);

        var result = OperationResult.Create(success, code, message);

        if (success)
        {
            _logger.Info("WarehouseTask.Confirm", new
            {
                _session.UserId,
                _session.SessionId,
                TaskId = taskId,
                Destination = destination,
                ResultCode = code,
                Success = true
            });
        }
        else
        {
            _logger.Warn("WarehouseTask.Confirm", new
            {
                _session.UserId,
                _session.SessionId,
                TaskId = taskId,
                Destination = destination,
                ResultCode = code,
                Success = false
            });
        }

        return result;
    }
}
