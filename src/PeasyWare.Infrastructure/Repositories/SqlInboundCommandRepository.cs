using Microsoft.Data.SqlClient;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// Command repository for inbound operations.
///
/// Responsibilities:
/// - Executes inbound-related commands
/// - Enforces session validity
/// - Uses session context for audit and traceability
/// - Produces structured, flat, queryable logs (NO nested context)
/// </summary>
public sealed class SqlInboundCommandRepository
    : RepositoryBase, IInboundCommandRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger _logger;

    public SqlInboundCommandRepository(
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

    // --------------------------------------------------
    // Activate inbound by ID
    // --------------------------------------------------

    public OperationResult ActivateInbound(int inboundId)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "deliveries.usp_activate_inbound";
        command.CommandType = CommandType.StoredProcedure;
        command.Parameters.AddWithValue("@inbound_id", inboundId);
        command.Parameters.AddWithValue("@user_id", _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            return BuildResult(
                action: "Inbound.Activate",
                resultCode: "ERRINB99",
                data: new { InboundId = inboundId });
        }

        var code = reader.GetString(1);

        return BuildResult(
            action: "Inbound.Activate",
            resultCode: code,
            data: new { InboundId = inboundId });
    }

    // --------------------------------------------------
    // Activate inbound by reference
    // --------------------------------------------------

    public OperationResult ActivateInboundByRef(string inboundRef)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);

        var inboundId = ResolveInboundId(connection, inboundRef);

        if (inboundId <= 0)
        {
            return BuildResult(
                action: "Inbound.ActivateByRef",
                resultCode: "ERRINB01",
                data: new { InboundRef = inboundRef });
        }

        return ActivateInbound(inboundId);
    }

    // --------------------------------------------------
    // Receive inbound line
    // --------------------------------------------------

    public OperationResult ReceiveInboundLine(
        int inboundLineId,
        int receivedQty,
        string stagingBinCode,
        int? inboundExpectedUnitId = null,
        string? externalRef = null,
        string? batchNumber = null,
        DateTime? bestBeforeDate = null,
        Guid? claimToken = null)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "deliveries.usp_receive_inbound_line";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@inbound_line_id", inboundLineId);
        command.Parameters.AddWithValue("@received_qty", receivedQty);
        command.Parameters.AddWithValue("@staging_bin_code", stagingBinCode);
        command.Parameters.AddWithValue("@external_ref", (object?)externalRef ?? DBNull.Value);
        command.Parameters.AddWithValue("@batch_number", (object?)batchNumber ?? DBNull.Value);
        command.Parameters.AddWithValue("@best_before_date", (object?)bestBeforeDate ?? DBNull.Value);
        command.Parameters.AddWithValue("@inbound_expected_unit_id", (object?)inboundExpectedUnitId ?? DBNull.Value);
        command.Parameters.AddWithValue("@claim_token", (object?)claimToken ?? DBNull.Value);
        command.Parameters.AddWithValue("@user_id", _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            return BuildResult(
                action: "Inbound.ReceiveLine",
                resultCode: "ERRINBL99",
                data: new
                {
                    InboundLineId = inboundLineId,
                    ExternalRef = externalRef,
                    BinCode = stagingBinCode
                });
        }

        var code = reader.GetString(1);

        int resolvedLineId = reader.IsDBNull(2) ? 0 : reader.GetInt32(2);
        int inboundId = reader.IsDBNull(3) ? 0 : reader.GetInt32(3);
        bool isClosed = !reader.IsDBNull(4) && reader.GetBoolean(4);

        var result = BuildResult(
            action: "Inbound.ReceiveLine",
            resultCode: code,
            data: new
            {
                InboundId = inboundId,
                InboundLineId = resolvedLineId,
                InboundExpectedUnitId = inboundExpectedUnitId,
                ExternalRef = externalRef,
                BinCode = stagingBinCode
            });

        if (result.Success && isClosed)
        {
            _logger.Info("Inbound.Closed", new
            {
                _session.UserId,
                _session.SessionId,
                _session.CorrelationId,
                ResultCode = "SUCINBCLS01",
                Success = true,
                Data = new
                {
                    InboundId = inboundId,
                    FinalStatus = "CLS"
                }
            });
        }

        return result;
    }

    // --------------------------------------------------
    // 🔥 Reverse inbound receipt
    // --------------------------------------------------

    public OperationResult ReverseInboundReceipt(
        int receiptId,
        string? reasonCode = null,
        string? reasonText = null)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "deliveries.usp_reverse_inbound_receipt";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@receipt_id", receiptId);
        command.Parameters.AddWithValue("@reason_code", (object?)reasonCode ?? DBNull.Value);
        command.Parameters.AddWithValue("@reason_text", (object?)reasonText ?? DBNull.Value);
        command.Parameters.AddWithValue("@user_id", _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            return BuildResult(
                action: "Inbound.ReceiveLine.Reversed",
                resultCode: "ERRINBREV99",
                data: new { ReceiptId = receiptId });
        }

        var code = reader.GetString(1);

        int inboundId = reader.IsDBNull(2) ? 0 : reader.GetInt32(2);
        int inboundLineId = reader.IsDBNull(3) ? 0 : reader.GetInt32(3);
        int originalReceiptId = reader.IsDBNull(4) ? 0 : reader.GetInt32(4);
        int reversalReceiptId = reader.IsDBNull(5) ? 0 : reader.GetInt32(5);
        int inventoryUnitId = reader.IsDBNull(6) ? 0 : reader.GetInt32(6);
        bool headerReopened = !reader.IsDBNull(7) && reader.GetBoolean(7);

        var result = BuildResult(
            action: "Inbound.ReceiveLine.Reversed",
            resultCode: code,
            data: new
            {
                InboundId = inboundId,
                InboundLineId = inboundLineId,
                ReceiptId = originalReceiptId,
                ReversalReceiptId = reversalReceiptId,
                InventoryUnitId = inventoryUnitId,
                ReasonCode = reasonCode
            });

        if (result.Success && headerReopened)
        {
            _logger.Info("Inbound.Reopened", new
            {
                _session.UserId,
                _session.SessionId,
                _session.CorrelationId,
                ResultCode = "SUCINBREOPEN01",
                Success = true,
                Data = new
                {
                    InboundId = inboundId,
                    PreviousStatus = "CLS",
                    NewStatus = "RCV",
                    TriggerReceiptId = originalReceiptId
                }
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Resolve inbound ID
    // --------------------------------------------------

    private static int ResolveInboundId(SqlConnection connection, string inboundRef)
    {
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT inbound_id
            FROM deliveries.inbound_deliveries
            WHERE inbound_ref = @ref
        """;

        command.Parameters.AddWithValue("@ref", inboundRef);

        var result = command.ExecuteScalar();

        return result is int inboundId ? inboundId : -1;
    }

    // --------------------------------------------------
    // Shared result builder (FLAT + STANDARDISED)
    // --------------------------------------------------

    private OperationResult BuildResult(
        string action,
        string resultCode,
        object data)
    {
        var success = resultCode.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);
        var message = _resolver.Resolve(resultCode);

        var result = OperationResult.Create(success, resultCode, message);

        var payload = new
        {
            _session.UserId,
            _session.SessionId,
            _session.CorrelationId,
            ResultCode = resultCode,
            Success = success,
            Data = data
        };

        if (success)
            _logger.Info(action, payload);
        else
            _logger.Warn(action, payload);

        return result;
    }
}