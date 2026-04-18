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

public sealed class SqlOutboundCommandRepository
    : RepositoryBase, IOutboundCommandRepository
{
    private readonly SqlConnectionFactory  _factory;
    private readonly SessionContext        _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;

    public SqlOutboundCommandRepository(
        SqlConnectionFactory  factory,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard)
        : base(sessionGuard, session.SessionId)
    {
        _factory  = factory  ?? throw new ArgumentNullException(nameof(factory));
        _session  = session  ?? throw new ArgumentNullException(nameof(session));
        _resolver = resolver ?? throw new ArgumentNullException(nameof(resolver));
        _logger   = logger   ?? throw new ArgumentNullException(nameof(logger));
    }

    // ────────────────────────────────────────────────────────
    // Create pick task
    // ────────────────────────────────────────────────────────

    public PickTaskResult CreatePickTask(int allocationId, string? destinationBinCode)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_pick_create";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@allocation_id", SqlDbType.Int).Value              = allocationId;
        command.Parameters.Add("@user_id",        SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",     SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        var destParam = command.Parameters.Add("@destination_bin_code", SqlDbType.NVarChar, 100);
        destParam.Value = destinationBinCode is not null ? (object)destinationBinCode.Trim() : DBNull.Value;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from pick task creation.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("Outbound.Pick.Create", new { _session.UserId, AllocationId = allocationId, ResultCode = code });
            return new PickTaskResult { Success = false, ResultCode = code, FriendlyMessage = message };
        }

        var result = new PickTaskResult
        {
            Success            = true,
            ResultCode         = code,
            FriendlyMessage    = message,
            TaskId             = reader.GetInt32(reader.GetOrdinal("task_id")),
            InventoryUnitId    = reader.IsDBNull(reader.GetOrdinal("inventory_unit_id"))    ? 0            : reader.GetInt32(reader.GetOrdinal("inventory_unit_id")),
            SourceBinCode      = reader.IsDBNull(reader.GetOrdinal("source_bin_code"))      ? string.Empty : reader.GetString(reader.GetOrdinal("source_bin_code")),
            DestinationBinCode = reader.IsDBNull(reader.GetOrdinal("destination_bin_code")) ? string.Empty : reader.GetString(reader.GetOrdinal("destination_bin_code"))
        };

        _logger.Info("Outbound.Pick.Create", new { _session.UserId, AllocationId = allocationId, result.TaskId, ResultCode = code });
        return result;
    }

    // ────────────────────────────────────────────────────────
    // Confirm pick task
    // ────────────────────────────────────────────────────────

    public OperationResult ConfirmPickTask(int taskId, string scannedBinCode, string scannedSscc)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_pick_confirm";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@task_id",          SqlDbType.Int).Value              = taskId;
        command.Parameters.Add("@scanned_bin_code", SqlDbType.NVarChar, 100).Value    = scannedBinCode.Trim();
        command.Parameters.Add("@scanned_sscc",     SqlDbType.NVarChar, 100).Value    = scannedSscc.Trim();
        command.Parameters.Add("@user_id",          SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",       SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from pick confirmation.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var message = _resolver.Resolve(code);
        var result  = OperationResult.Create(success, code, message);

        if (success) _logger.Info("Outbound.Pick.Confirm", new { _session.UserId, TaskId = taskId, ResultCode = code });
        else         _logger.Warn("Outbound.Pick.Confirm", new { _session.UserId, TaskId = taskId, ResultCode = code });

        return result;
    }

    // ────────────────────────────────────────────────────────
    // Confirm load — order-level confirmation, no SSCC scanning
    // Operator confirms an order is physically on the vehicle
    // ────────────────────────────────────────────────────────

    public LoadConfirmResult ConfirmLoad(int outboundOrderId, int shipmentId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_confirm_load";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@outbound_order_id", SqlDbType.Int).Value              = outboundOrderId;
        command.Parameters.Add("@shipment_id",        SqlDbType.Int).Value              = shipmentId;
        command.Parameters.Add("@user_id",            SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",         SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from load confirmation.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("Outbound.Load.Confirm", new { _session.UserId, OutboundOrderId = outboundOrderId, ShipmentId = shipmentId, ResultCode = code });
            return new LoadConfirmResult { Success = false, ResultCode = code, FriendlyMessage = message };
        }

        _logger.Info("Outbound.Load.Confirm", new { _session.UserId, OutboundOrderId = outboundOrderId, ShipmentId = shipmentId, ResultCode = code });
        return new LoadConfirmResult { Success = true, ResultCode = code, FriendlyMessage = message };
    }

    // ────────────────────────────────────────────────────────
    // Ship — confirm departure
    // ────────────────────────────────────────────────────────

    public ShipResult Ship(int shipmentId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_ship";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@shipment_id", SqlDbType.Int).Value              = shipmentId;
        command.Parameters.Add("@user_id",     SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",  SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from ship.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var message = _resolver.Resolve(code);

        if (!success)
        {
            _logger.Warn("Outbound.Ship", new { _session.UserId, ShipmentId = shipmentId, ResultCode = code });
            return new ShipResult { Success = false, ResultCode = code, FriendlyMessage = message };
        }

        var result = new ShipResult
        {
            Success         = true,
            ResultCode      = code,
            FriendlyMessage = message,
            UnitsShipped    = reader.IsDBNull(reader.GetOrdinal("units_shipped")) ? 0 : reader.GetInt32(reader.GetOrdinal("units_shipped"))
        };

        _logger.Info("Outbound.Ship", new { _session.UserId, ShipmentId = shipmentId, result.UnitsShipped, ResultCode = code });
        return result;
    }
}
