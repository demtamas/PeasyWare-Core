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
/// Covers: putaway, bin-to-bin movement.
/// </summary>
public sealed class SqlWarehouseTaskCommandRepository
    : RepositoryBase, IWarehouseTaskCommandRepository
{
    private readonly SqlConnectionFactory  _factory;
    private readonly SessionContext        _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;

    public SqlWarehouseTaskCommandRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session, resolver, logger)
    {
        _factory  = factory  ?? throw new ArgumentNullException(nameof(factory));
        _session  = session  ?? throw new ArgumentNullException(nameof(session));
        _resolver = resolver ?? throw new ArgumentNullException(nameof(resolver));
        _logger   = logger   ?? throw new ArgumentNullException(nameof(logger));
    }

    // ────────────────────────────────────────────────────────
    // Putaway — create task
    // ────────────────────────────────────────────────────────

    public PutawayTaskResult CreatePutawayTask(int inventoryUnitId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_putaway_create_task_for_unit";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@inventory_unit_id", SqlDbType.Int).Value        = inventoryUnitId;
        command.Parameters.Add("@user_id",           SqlDbType.Int).Value        = _session.UserId;
        command.Parameters.Add("@session_id",        SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from putaway task creation.");

        var colSuccess    = reader.GetOrdinal("success");
        var colCode       = reader.GetOrdinal("result_code");
        var colTaskId     = reader.GetOrdinal("task_id");
        var colDestBin    = reader.GetOrdinal("destination_bin_code");
        var colUnitId     = reader.GetOrdinal("inventory_unit_id");
        var colSourceBin  = reader.GetOrdinal("source_bin_code");
        var colStockState = reader.GetOrdinal("stock_state_code");
        var colStockStatus= reader.GetOrdinal("stock_status_code");
        var colExpiresAt  = reader.GetOrdinal("expires_at");
        var colZone       = reader.GetOrdinal("zone_code");

        var success = reader.GetBoolean(colSuccess);
        var code    = reader.GetString(colCode);
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("WarehouseTask.Create", new
            {
                _session.UserId, _session.SessionId,
                InventoryUnitId = inventoryUnitId,
                ResultCode = code, Success = false
            });

            return new PutawayTaskResult
            {
                Success = false, ResultCode = code, FriendlyMessage = message
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
            _session.UserId, _session.SessionId,
            InventoryUnitId = inventoryUnitId,
            result.TaskId, result.DestinationBinCode,
            ResultCode = code, Success = true
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Putaway — confirm task
    // ────────────────────────────────────────────────────────

    public OperationResult ConfirmPutawayTask(int taskId, string destination)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_putaway_confirm_task";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@task_id",          SqlDbType.Int).Value            = taskId;
        command.Parameters.Add("@scanned_bin_code", SqlDbType.NVarChar, 100).Value  = destination;
        command.Parameters.Add("@user_id",          SqlDbType.Int).Value            = _session.UserId;
        command.Parameters.Add("@session_id",       SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from putaway confirmation.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult(
            action:     "WarehouseTask.Confirm",
            resultCode: code,
            data:       new { TaskId = taskId, Destination = destination });
    }

    // ────────────────────────────────────────────────────────
    // Bin-to-bin — create task
    // destinationBinCode = null → request suggestion from SP
    // ────────────────────────────────────────────────────────

    public BinMoveTaskResult CreateBinMoveTask(string externalRef, string? destinationBinCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_bin_to_bin_move_create";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@external_ref",         SqlDbType.NVarChar, 100).Value = externalRef.Trim();
        command.Parameters.Add("@user_id",              SqlDbType.Int).Value            = _session.UserId;
        command.Parameters.Add("@session_id",           SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        var destParam = command.Parameters.Add("@destination_bin_code", SqlDbType.NVarChar, 100);
        destParam.Value = destinationBinCode is not null
            ? (object)destinationBinCode.Trim()
            : DBNull.Value;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from bin-to-bin move creation.");

        var colSuccess  = reader.GetOrdinal("success");
        var colCode     = reader.GetOrdinal("result_code");
        var colTaskId   = reader.GetOrdinal("task_id");
        var colUnitId   = reader.GetOrdinal("inventory_unit_id");
        var colSrcBin   = reader.GetOrdinal("source_bin_code");
        var colDestBin  = reader.GetOrdinal("destination_bin_code");

        var success = reader.GetBoolean(colSuccess);
        var code    = reader.GetString(colCode);
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("WarehouseTask.BinMove.Create", new
            {
                _session.UserId, _session.SessionId,
                ExternalRef = externalRef, ResultCode = code, Success = false
            });

            return new BinMoveTaskResult
            {
                Success = false, ResultCode = code, FriendlyMessage = message
            };
        }

        var result = new BinMoveTaskResult
        {
            Success            = true,
            ResultCode         = code,
            FriendlyMessage    = message,
            TaskId             = reader.GetInt32(colTaskId),
            InventoryUnitId    = reader.GetInt32(colUnitId),
            SourceBinCode      = reader.IsDBNull(colSrcBin)  ? string.Empty : reader.GetString(colSrcBin),
            DestinationBinCode = reader.IsDBNull(colDestBin) ? string.Empty : reader.GetString(colDestBin)
        };

        _logger.Info("WarehouseTask.BinMove.Create", new
        {
            _session.UserId, _session.SessionId,
            ExternalRef = externalRef,
            result.TaskId, result.SourceBinCode, result.DestinationBinCode,
            ResultCode = code, Success = true
        });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Bin-to-bin — confirm task
    // ────────────────────────────────────────────────────────

    public OperationResult ConfirmBinMoveTask(int taskId, string scannedBinCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "warehouse.usp_bin_to_bin_move_confirm";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@task_id",          SqlDbType.Int).Value              = taskId;
        command.Parameters.Add("@scanned_bin_code", SqlDbType.NVarChar, 100).Value    = scannedBinCode.Trim();
        command.Parameters.Add("@user_id",          SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",       SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException(
                "Unexpected empty response from bin-to-bin move confirmation.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult(
            action:     "WarehouseTask.BinMove.Confirm",
            resultCode: code,
            data:       new { TaskId = taskId, ScannedBin = scannedBinCode });
    }
}
