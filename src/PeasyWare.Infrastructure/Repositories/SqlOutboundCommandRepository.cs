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
        : base(sessionGuard, session, resolver, logger)
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

        return BuildResult(
            action:     "Outbound.Pick.Confirm",
            resultCode: code,
            data:       new { TaskId = taskId, ScannedBin = scannedBinCode, ScannedSscc = scannedSscc });
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

    public ShipResult Ship(int shipmentId, string vehicleRef)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_ship";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add("@shipment_id", SqlDbType.Int).Value              = shipmentId;
        command.Parameters.Add("@vehicle_ref", SqlDbType.NVarChar, 50).Value     = vehicleRef.Trim();
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

    // ────────────────────────────────────────────────────────
    // API creation methods
    // ────────────────────────────────────────────────────────

    public OperationResult CreateOrder(
        string             orderRef,
        string             customerPartyCode,
        string?            haulierPartyCode  = null,
        string?            deliveryPartyCode = null,
        DateTime?          requiredDate      = null,
        string?            notes             = null,
        List<OrderLineDto> lines             = null!)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_create_order";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",              _session.UserId);
        command.Parameters.AddWithValue("@session_id",           _session.SessionId);
        command.Parameters.Add(new SqlParameter("@order_ref",            SqlDbType.NVarChar, 50)   { Value = orderRef });
        command.Parameters.Add(new SqlParameter("@customer_party_code",  SqlDbType.NVarChar, 50)   { Value = customerPartyCode });
        command.Parameters.Add(new SqlParameter("@haulier_party_code",   SqlDbType.NVarChar, 50)   { Value = (object?)haulierPartyCode  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@delivery_party_code",  SqlDbType.NVarChar, 50)   { Value = (object?)deliveryPartyCode ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@required_date",        SqlDbType.Date)           { Value = (object?)requiredDate      ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@notes",                SqlDbType.NVarChar, 500)  { Value = (object?)notes             ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@lines_json",           SqlDbType.NVarChar, -1)   { Value = System.Text.Json.JsonSerializer.Serialize(lines) });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRORD99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));
        var orderId = success ? reader.GetInt32(reader.GetOrdinal("outbound_order_id")) : 0;

        return BuildResult("Outbound.CreateOrder", code, new { OrderRef = orderRef, OrderId = orderId });
    }

    public OperationResult CreateShipment(
        string    shipmentRef,
        string    haulierPartyCode,
        string?   vehicleRef       = null,
        DateTime? plannedDeparture = null,
        string?   notes            = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_create_shipment";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",             _session.UserId);
        command.Parameters.AddWithValue("@session_id",          _session.SessionId);
        command.Parameters.Add(new SqlParameter("@shipment_ref",        SqlDbType.NVarChar, 50)  { Value = shipmentRef });
        command.Parameters.Add(new SqlParameter("@haulier_party_code",  SqlDbType.NVarChar, 50)  { Value = haulierPartyCode });
        command.Parameters.Add(new SqlParameter("@vehicle_ref",         SqlDbType.NVarChar, 50)  { Value = (object?)vehicleRef       ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@planned_departure",   SqlDbType.DateTime2)     { Value = (object?)plannedDeparture ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@notes",               SqlDbType.NVarChar, 500) { Value = (object?)notes            ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRSHIP99", "Unexpected error.");

        var success    = reader.GetBoolean(reader.GetOrdinal("success"));
        var code       = reader.GetString(reader.GetOrdinal("result_code"));
        var shipmentId = success ? reader.GetInt32(reader.GetOrdinal("shipment_id")) : 0;

        return BuildResult("Outbound.CreateShipment", code, new { ShipmentRef = shipmentRef, ShipmentId = shipmentId });
    }

    public OperationResult CancelAllocation(int allocationId, string? reason = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_cancel_allocation";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@allocation_id", SqlDbType.Int)          { Value = allocationId });
        command.Parameters.Add(new SqlParameter("@reason",        SqlDbType.NVarChar, 200) { Value = (object?)reason ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRALLOC99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Outbound.CancelAllocation", code,
            new { AllocationId = allocationId, Reason = reason });
    }

    public OperationResult ReallocateLine(int outboundLineId)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_reallocate_line";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@outbound_line_id", SqlDbType.Int) { Value = outboundLineId });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRALLOC99", "Unexpected error.");

        var success      = reader.GetBoolean(reader.GetOrdinal("success"));
        var code         = reader.GetString(reader.GetOrdinal("result_code"));
        var allocationId = success ? reader.GetInt32(reader.GetOrdinal("allocation_id")) : 0;

        return BuildResult("Outbound.ReallocateLine", code,
            new { OutboundLineId = outboundLineId, NewAllocationId = allocationId });
    }

    public OperationResult AddOrderToShipment(
        string shipmentRef,
        string orderRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_add_order_to_shipment";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",    _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.Parameters.Add(new SqlParameter("@shipment_ref", SqlDbType.NVarChar, 50) { Value = shipmentRef });
        command.Parameters.Add(new SqlParameter("@order_ref",    SqlDbType.NVarChar, 50) { Value = orderRef });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRSHIP99", "Unexpected error.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        var code    = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Outbound.AddOrderToShipment", code,
            new { ShipmentRef = shipmentRef, OrderRef = orderRef });
    }

    public OperationResult CancelShipment(
        string  shipmentRef,
        string? reason = null)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "outbound.usp_cancel_shipment";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(new SqlParameter("@shipment_ref", SqlDbType.NVarChar, 50)  { Value = shipmentRef });
        command.Parameters.Add(new SqlParameter("@reason",       SqlDbType.NVarChar, 200) { Value = (object?)reason ?? DBNull.Value });
        command.Parameters.AddWithValue("@user_id",        _session.UserId);
        command.Parameters.AddWithValue("@session_id",     _session.SessionId);
        command.Parameters.AddWithValue("@correlation_id", _session.CorrelationId);

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return BuildResult("Outbound.CancelShipment", "ERRSHIP99", new { ShipmentRef = shipmentRef });

        var code = reader.GetString(reader.GetOrdinal("result_code"));
        return BuildResult("Outbound.CancelShipment", code, new { ShipmentRef = shipmentRef });
    }

    // ────────────────────────────────────────────────────────
    // Allocate order (Desktop — calls existing usp_allocate_order)
    // ────────────────────────────────────────────────────────

    public OperationResult AllocateOrder(int outboundOrderId, bool allowPartial = false)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "outbound.usp_allocate_order";
        command.CommandType = System.Data.CommandType.StoredProcedure;

        command.Parameters.Add("@outbound_order_id", System.Data.SqlDbType.Int).Value              = outboundOrderId;
        command.Parameters.Add("@allow_partial",     System.Data.SqlDbType.Bit).Value              = allowPartial;
        command.Parameters.Add("@user_id",           System.Data.SqlDbType.Int).Value              = _session.UserId;
        command.Parameters.Add("@session_id",        System.Data.SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from usp_allocate_order.");

        var code = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Outbound.AllocateOrder", code,
            new { OutboundOrderId = outboundOrderId });
    }

    // ────────────────────────────────────────────────────────
    // Deallocate order (Desktop — calls outbound.usp_deallocate_order)
    // ────────────────────────────────────────────────────────

    public OperationResult DeallocateOrder(int outboundOrderId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "outbound.usp_deallocate_order";
        command.CommandType = System.Data.CommandType.StoredProcedure;

        command.Parameters.Add("@outbound_order_id", System.Data.SqlDbType.Int).Value = outboundOrderId;
        command.Parameters.Add("@user_id", System.Data.SqlDbType.Int).Value = _session.UserId;
        command.Parameters.Add("@session_id", System.Data.SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from usp_deallocate_order.");

        var code = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Outbound.DeallocateOrder", code,
            new { OutboundOrderId = outboundOrderId });
    }

    // ────────────────────────────────────────────────────────
    // Cancel order — hard-refuses if anything is beyond NEW
    // ────────────────────────────────────────────────────────

    public OperationResult CancelOrder(int outboundOrderId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "outbound.usp_cancel_order";
        command.CommandType = System.Data.CommandType.StoredProcedure;

        command.Parameters.Add("@outbound_order_id", System.Data.SqlDbType.Int).Value = outboundOrderId;
        command.Parameters.Add("@user_id", System.Data.SqlDbType.Int).Value = _session.UserId;
        command.Parameters.Add("@session_id", System.Data.SqlDbType.UniqueIdentifier).Value = _session.SessionId;

        using var reader = command.ExecuteReader();

        if (!reader.Read())
            throw new InvalidOperationException("Unexpected empty response from usp_cancel_order.");

        var code = reader.GetString(reader.GetOrdinal("result_code"));

        return BuildResult("Outbound.CancelOrder", code,
            new { OutboundOrderId = outboundOrderId });
    }

}
