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
        : base(sessionGuard, session, resolver, logger)
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

        command.CommandText = "inbound.usp_activate_inbound";
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

        var colCode      = reader.GetOrdinal("result_code");
        var colInboundId = reader.GetOrdinal("inbound_id");

        var code           = reader.GetString(colCode);
        var resolvedId     = reader.IsDBNull(colInboundId) ? inboundId : reader.GetInt32(colInboundId);

        return BuildResult(
            action: "Inbound.Activate",
            resultCode: code,
            data: new { InboundId = resolvedId });
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

        command.CommandText = "inbound.usp_receive_inbound_line";
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
                    ExternalRef   = externalRef,
                    BinCode       = stagingBinCode
                });
        }

        var colCode      = reader.GetOrdinal("result_code");
        var colLineId    = reader.GetOrdinal("inbound_line_id");
        var colInboundId = reader.GetOrdinal("inbound_id");
        var colIsClosed  = reader.GetOrdinal("is_closed");

        var code           = reader.GetString(colCode);
        var resolvedLineId = reader.IsDBNull(colLineId)    ? 0     : reader.GetInt32(colLineId);
        var inboundId      = reader.IsDBNull(colInboundId) ? 0     : reader.GetInt32(colInboundId);
        var isClosed       = !reader.IsDBNull(colIsClosed) && reader.GetBoolean(colIsClosed);

        var result = BuildResult(
            action: "Inbound.ReceiveLine",
            resultCode: code,
            data: new
            {
                InboundId             = inboundId,
                InboundLineId         = resolvedLineId,
                InboundExpectedUnitId = inboundExpectedUnitId,
                ExternalRef           = externalRef,
                BinCode               = stagingBinCode
            });

        if (result.Success && isClosed)
        {
            _logger.Info("Inbound.Closed", new
            {
                _session.UserId,
                _session.SessionId,
                _session.CorrelationId,
                ResultCode = "SUCINBCLS01",
                Success    = true,
                Data = new
                {
                    InboundId   = inboundId,
                    FinalStatus = "CLS"
                }
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Reverse inbound receipt
    // --------------------------------------------------

    public OperationResult ReverseInboundReceipt(
        int receiptId,
        string? reasonCode = null,
        string? reasonText = null)
    {
        EnsureSession();

        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "inbound.usp_reverse_inbound_receipt";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@receipt_id",   receiptId);
        command.Parameters.AddWithValue("@reason_code",  (object?)reasonCode  ?? DBNull.Value);
        command.Parameters.AddWithValue("@reason_text",  (object?)reasonText  ?? DBNull.Value);
        command.Parameters.AddWithValue("@user_id",      _session.UserId);
        command.Parameters.AddWithValue("@session_id",   _session.SessionId);

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            return BuildResult(
                action: "Inbound.ReceiveLine.Reversed",
                resultCode: "ERRINBREV99",
                data: new { ReceiptId = receiptId });
        }

        var colCode              = reader.GetOrdinal("result_code");
        var colInboundId         = reader.GetOrdinal("inbound_id");
        var colLineId            = reader.GetOrdinal("inbound_line_id");
        var colReceiptId         = reader.GetOrdinal("receipt_id");
        var colReversalReceiptId = reader.GetOrdinal("reversal_receipt_id");
        var colInventoryUnitId   = reader.GetOrdinal("inventory_unit_id");
        var colHeaderReopened    = reader.GetOrdinal("header_reopened");

        var code              = reader.GetString(colCode);
        var inboundId         = reader.IsDBNull(colInboundId)         ? 0     : reader.GetInt32(colInboundId);
        var inboundLineId     = reader.IsDBNull(colLineId)            ? 0     : reader.GetInt32(colLineId);
        var originalReceiptId = reader.IsDBNull(colReceiptId)         ? 0     : reader.GetInt32(colReceiptId);
        var reversalReceiptId = reader.IsDBNull(colReversalReceiptId) ? 0     : reader.GetInt32(colReversalReceiptId);
        var inventoryUnitId   = reader.IsDBNull(colInventoryUnitId)   ? 0     : reader.GetInt32(colInventoryUnitId);
        var headerReopened    = !reader.IsDBNull(colHeaderReopened)   && reader.GetBoolean(colHeaderReopened);

        var result = BuildResult(
            action: "Inbound.ReceiveLine.Reversed",
            resultCode: code,
            data: new
            {
                InboundId         = inboundId,
                InboundLineId     = inboundLineId,
                ReceiptId         = originalReceiptId,
                ReversalReceiptId = reversalReceiptId,
                InventoryUnitId   = inventoryUnitId,
                ReasonCode        = reasonCode
            });

        if (result.Success && headerReopened)
        {
            _logger.Info("Inbound.Reopened", new
            {
                _session.UserId,
                _session.SessionId,
                _session.CorrelationId,
                ResultCode = "SUCINBREOPEN01",
                Success    = true,
                Data = new
                {
                    InboundId        = inboundId,
                    PreviousStatus   = "CLS",
                    NewStatus        = "RCV",
                    TriggerReceiptId = originalReceiptId
                }
            });
        }

        return result;
    }

    // --------------------------------------------------
    // Resolve inbound ID
    // --------------------------------------------------

    // ──────────────────────────────────────────────────────────────────────
    // API creation methods
    // ──────────────────────────────────────────────────────────────────────

    public OperationResult CreateInbound(
        string    inboundRef,
        string    supplierPartyCode,
        string?   haulierPartyCode  = null,
        DateTime? expectedArrivalAt = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inbound.usp_create_inbound";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",             _session.UserId);
        command.Parameters.AddWithValue("@session_id",          _session.SessionId);
        command.Parameters.Add(new SqlParameter("@inbound_ref",         SqlDbType.NVarChar, 50)  { Value = inboundRef });
        command.Parameters.Add(new SqlParameter("@supplier_party_code", SqlDbType.NVarChar, 50)  { Value = supplierPartyCode });
        command.Parameters.Add(new SqlParameter("@haulier_party_code",  SqlDbType.NVarChar, 50)  { Value = (object?)haulierPartyCode  ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@expected_arrival_at", SqlDbType.DateTime2)     { Value = (object?)expectedArrivalAt ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRINB99", "Unexpected error.");

        var success    = reader.GetBoolean(reader.GetOrdinal("success"));
        var code       = reader.GetString(reader.GetOrdinal("result_code"));
        var inboundId  = success ? reader.GetInt32(reader.GetOrdinal("inbound_id")) : 0;

        return BuildResult("Inbound.Create", code, new { InboundRef = inboundRef, InboundId = inboundId });
    }

    public OperationResult AddInboundLine(
        string    inboundRef,
        string    skuCode,
        int       expectedQty,
        string?   batchNumber        = null,
        DateTime? bestBeforeDate     = null,
        string    arrivalStockStatus = "AV")
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inbound.usp_create_inbound_line";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",              _session.UserId);
        command.Parameters.AddWithValue("@session_id",           _session.SessionId);
        command.Parameters.Add(new SqlParameter("@inbound_ref",          SqlDbType.NVarChar, 50)  { Value = inboundRef });
        command.Parameters.Add(new SqlParameter("@sku_code",             SqlDbType.NVarChar, 50)  { Value = skuCode });
        command.Parameters.Add(new SqlParameter("@expected_qty",         SqlDbType.Int)           { Value = expectedQty });
        command.Parameters.Add(new SqlParameter("@batch_number",         SqlDbType.NVarChar, 100) { Value = (object?)batchNumber    ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@best_before_date",     SqlDbType.Date)          { Value = (object?)bestBeforeDate ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@arrival_stock_status", SqlDbType.NVarChar, 2)   { Value = arrivalStockStatus });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRINB99", "Unexpected error.");

        var success      = reader.GetBoolean(reader.GetOrdinal("success"));
        var code         = reader.GetString(reader.GetOrdinal("result_code"));
        var lineId       = success ? reader.GetInt32(reader.GetOrdinal("inbound_line_id")) : 0;
        var inboundId    = success ? reader.GetInt32(reader.GetOrdinal("inbound_id"))      : 0;

        return BuildResult("Inbound.AddLine", code,
            new { InboundRef = inboundRef, SkuCode = skuCode, InboundLineId = lineId });
    }

    public OperationResult AddExpectedUnit(
        string    inboundRef,
        string    sscc,
        int       quantity,
        string?   batchNumber    = null,
        DateTime? bestBeforeDate = null)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command    = connection.CreateCommand();

        command.CommandText = "inbound.usp_create_expected_unit";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id",            _session.UserId);
        command.Parameters.AddWithValue("@session_id",         _session.SessionId);
        command.Parameters.Add(new SqlParameter("@inbound_ref",       SqlDbType.NVarChar, 50)  { Value = inboundRef });
        command.Parameters.Add(new SqlParameter("@sscc",              SqlDbType.NVarChar, 18)  { Value = sscc });
        command.Parameters.Add(new SqlParameter("@quantity",          SqlDbType.Int)           { Value = quantity });
        command.Parameters.Add(new SqlParameter("@batch_number",      SqlDbType.NVarChar, 100) { Value = (object?)batchNumber    ?? DBNull.Value });
        command.Parameters.Add(new SqlParameter("@best_before_date",  SqlDbType.Date)          { Value = (object?)bestBeforeDate ?? DBNull.Value });

        using var reader = command.ExecuteReader();
        if (!reader.Read()) return OperationResult.Create(false, "ERRINB99", "Unexpected error.");

        var success  = reader.GetBoolean(reader.GetOrdinal("success"));
        var code     = reader.GetString(reader.GetOrdinal("result_code"));
        var unitId   = success ? reader.GetInt32(reader.GetOrdinal("inbound_expected_unit_id")) : 0;

        return BuildResult("Inbound.AddExpectedUnit", code,
            new { InboundRef = inboundRef, Sscc = sscc, UnitId = unitId });
    }

    private static int ResolveInboundId(SqlConnection connection, string inboundRef)
    {
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT inbound_id
            FROM inbound.inbound_deliveries
            WHERE inbound_ref = @ref
        """;

        command.Parameters.AddWithValue("@ref", inboundRef);

        var result = command.ExecuteScalar();

        return result is int inboundId ? inboundId : -1;
    }

}
