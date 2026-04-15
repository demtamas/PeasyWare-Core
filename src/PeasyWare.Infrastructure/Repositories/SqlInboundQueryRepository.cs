using Microsoft.Data.SqlClient;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Collections.Generic;
using System.Data;

namespace PeasyWare.Infrastructure.Repositories;

/// <summary>
/// QUERY repository for inbound-related reads.
///
/// Responsibilities:
/// - Read-only access to inbound data
/// - Uses SessionContext only for DB context (audit / tracing)
/// - No session enforcement (UI handles expired session)
/// </summary>
public sealed class SqlInboundQueryRepository : IInboundQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly SessionContext _session;
    private readonly IErrorMessageResolver _resolver;

    public SqlInboundQueryRepository(
        SqlConnectionFactory factory,
        SessionContext session,
        IErrorMessageResolver resolver)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _session = session ?? throw new ArgumentNullException(nameof(session));
        _resolver = resolver ?? throw new ArgumentNullException(nameof(resolver));
    }

    // ------------------------------------------------------------
    // Activatable inbounds
    // ------------------------------------------------------------

    public IEnumerable<ActivatableInboundDto> GetActivatableInbounds()
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT inbound_id,
                   inbound_ref,
                   expected_arrival_at,
                   line_count
            FROM deliveries.vw_inbounds_activatable
            ORDER BY expected_arrival_at, inbound_ref
        """;

        using var reader = command.ExecuteReader();

        var colInboundId       = reader.GetOrdinal("inbound_id");
        var colInboundRef      = reader.GetOrdinal("inbound_ref");
        var colExpectedArrival = reader.GetOrdinal("expected_arrival_at");
        var colLineCount       = reader.GetOrdinal("line_count");

        while (reader.Read())
        {
            yield return new ActivatableInboundDto
            {
                InboundId         = reader.GetInt32(colInboundId),
                InboundRef        = reader.GetString(colInboundRef),
                ExpectedArrivalAt = reader.IsDBNull(colExpectedArrival) ? null : reader.GetDateTime(colExpectedArrival),
                LineCount         = reader.GetInt32(colLineCount)
            };
        }
    }

    // ------------------------------------------------------------
    // Receivable lines
    // ------------------------------------------------------------

    public IEnumerable<InboundLineDto> GetReceivableLines(string inboundRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT inbound_line_id,
                   line_no,
                   sku_code,
                   sku_description,
                   expected_qty,
                   received_qty,
                   outstanding_qty
            FROM deliveries.vw_inbound_lines_receivable
            WHERE inbound_ref = @ref
            ORDER BY line_no
        """;

        command.Parameters.Add(
            new SqlParameter("@ref", SqlDbType.NVarChar, 50)
            { Value = inboundRef });

        using var reader = command.ExecuteReader();

        var colLineId      = reader.GetOrdinal("inbound_line_id");
        var colLineNo      = reader.GetOrdinal("line_no");
        var colSkuCode     = reader.GetOrdinal("sku_code");
        var colSkuDesc     = reader.GetOrdinal("sku_description");
        var colExpected    = reader.GetOrdinal("expected_qty");
        var colReceived    = reader.GetOrdinal("received_qty");
        var colOutstanding = reader.GetOrdinal("outstanding_qty");

        while (reader.Read())
        {
            yield return new InboundLineDto
            {
                InboundLineId  = reader.GetInt32(colLineId),
                LineNo         = reader.GetInt32(colLineNo),
                SkuCode        = reader.GetString(colSkuCode),
                Description    = reader.GetString(colSkuDesc),
                ExpectedQty    = reader.GetInt32(colExpected),
                ReceivedQty    = reader.GetInt32(colReceived),
                OutstandingQty = reader.GetInt32(colOutstanding)
            };
        }
    }

    // ------------------------------------------------------------
    // Inbound summary
    // ------------------------------------------------------------

    public InboundSummaryDto GetInboundSummary(string inboundRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "deliveries.usp_get_inbound_summary";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.Add(
            new SqlParameter("@inbound_ref", SqlDbType.NVarChar, 50)
            { Value = inboundRef });

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            return new InboundSummaryDto
            {
                Exists = false,
                IsReceivable = false,
                HasExpectedUnits = false
            };
        }

        // Column names match SP aliases: ExistsFlag, IsReceivable, HasExpectedUnits
        var colExists           = reader.GetOrdinal("ExistsFlag");
        var colIsReceivable     = reader.GetOrdinal("IsReceivable");
        var colHasExpectedUnits = reader.GetOrdinal("HasExpectedUnits");

        return new InboundSummaryDto
        {
            Exists           = reader.GetBoolean(colExists),
            IsReceivable     = reader.GetBoolean(colIsReceivable),
            HasExpectedUnits = reader.GetBoolean(colHasExpectedUnits)
        };
    }

    // ------------------------------------------------------------
    // Outstanding SSCC count
    // ------------------------------------------------------------

    public int GetOutstandingSsccCount(string inboundRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT COUNT(1)
            FROM deliveries.inbound_expected_units eu
            JOIN deliveries.inbound_lines l
                ON eu.inbound_line_id = l.inbound_line_id
            JOIN deliveries.inbound_deliveries d
                ON l.inbound_id = d.inbound_id
            WHERE d.inbound_ref = @ref
              AND eu.received_inventory_unit_id IS NULL
        """;

        command.Parameters.Add(
            new SqlParameter("@ref", SqlDbType.NVarChar, 50)
            { Value = inboundRef });

        var result = command.ExecuteScalar();

        return result is int count ? count : Convert.ToInt32(result ?? 0);
    }

    // ------------------------------------------------------------
    // Receivable receipts (non-reversed, reversible state only)
    // ------------------------------------------------------------

    public IEnumerable<InboundReceiptDto> GetReceivableReceipts(string inboundRef)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = """
            SELECT
                r.receipt_id,
                r.inbound_line_id,
                r.inbound_expected_unit_id,
                r.inventory_unit_id,
                r.received_qty,
                r.received_at,
                r.is_reversal,
                r.reversed_receipt_id,
                iu.external_ref,
                iu.stock_state_code,
                b.bin_code          AS current_bin_code,
                d.inbound_ref,
                l.line_state_code
            FROM deliveries.inbound_receipts r
            JOIN inventory.inventory_units iu
                ON iu.inventory_unit_id = r.inventory_unit_id
            JOIN deliveries.inbound_lines l
                ON l.inbound_line_id = r.inbound_line_id
            JOIN deliveries.inbound_deliveries d
                ON d.inbound_id = l.inbound_id
            LEFT JOIN inventory.inventory_placements p
                ON p.inventory_unit_id = r.inventory_unit_id
            LEFT JOIN locations.bins b
                ON b.bin_id = p.bin_id
            WHERE d.inbound_ref  = @ref
              AND r.is_reversal  = 0
              AND r.reversed_receipt_id IS NULL
              AND iu.stock_state_code = 'RCD'
            ORDER BY r.receipt_id
        """;

        command.Parameters.Add(
            new SqlParameter("@ref", SqlDbType.NVarChar, 50)
            { Value = inboundRef });

        using var reader = command.ExecuteReader();

        var colReceiptId         = reader.GetOrdinal("receipt_id");
        var colLineId            = reader.GetOrdinal("inbound_line_id");
        var colExpectedUnitId    = reader.GetOrdinal("inbound_expected_unit_id");
        var colUnitId            = reader.GetOrdinal("inventory_unit_id");
        var colReceivedQty       = reader.GetOrdinal("received_qty");
        var colReceivedAt        = reader.GetOrdinal("received_at");
        var colIsReversal        = reader.GetOrdinal("is_reversal");
        var colReversedReceiptId = reader.GetOrdinal("reversed_receipt_id");
        var colExternalRef       = reader.GetOrdinal("external_ref");
        var colStateCode         = reader.GetOrdinal("stock_state_code");
        var colBinCode           = reader.GetOrdinal("current_bin_code");
        var colInboundRef        = reader.GetOrdinal("inbound_ref");
        var colLineState         = reader.GetOrdinal("line_state_code");

        while (reader.Read())
        {
            yield return new InboundReceiptDto
            {
                ReceiptId              = reader.GetInt32(colReceiptId),
                InboundLineId          = reader.GetInt32(colLineId),
                InboundExpectedUnitId  = reader.IsDBNull(colExpectedUnitId) ? null : reader.GetInt32(colExpectedUnitId),
                InventoryUnitId        = reader.GetInt32(colUnitId),
                ReceivedQty            = reader.GetInt32(colReceivedQty),
                ReceivedAt             = reader.GetDateTime(colReceivedAt),
                IsReversal             = reader.GetBoolean(colIsReversal),
                ReversedReceiptId      = reader.IsDBNull(colReversedReceiptId) ? null : reader.GetInt32(colReversedReceiptId),
                ExternalRef            = reader.IsDBNull(colExternalRef) ? null : reader.GetString(colExternalRef),
                StockStateCode         = reader.GetString(colStateCode),
                CurrentBinCode         = reader.IsDBNull(colBinCode) ? null : reader.GetString(colBinCode),
                InboundRef             = reader.GetString(colInboundRef),
                LineStateCode          = reader.GetString(colLineState)
            };
        }
    }

    // ------------------------------------------------------------
    // SSCC validation
    // ------------------------------------------------------------

    public SsccValidationDto ValidateSsccForInbound(
        string externalRef,
        string stagingBin)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "deliveries.usp_validate_sscc_for_receive";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@user_id", _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);

        command.Parameters.Add(
            new SqlParameter("@external_ref", SqlDbType.NVarChar, 50)
            { Value = externalRef });

        command.Parameters.Add(
            new SqlParameter("@staging_bin_code", SqlDbType.NVarChar, 50)
            { Value = stagingBin });

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            const string fallbackCode = "ERRSSCC99";

            return new SsccValidationDto
            {
                Success = false,
                ResultCode = fallbackCode,
                FriendlyMessage = _resolver.Resolve(fallbackCode)
            };
        }

        var colSuccess           = reader.GetOrdinal("success");
        var colCode              = reader.GetOrdinal("result_code");
        var colExpectedUnitId    = reader.GetOrdinal("inbound_expected_unit_id");
        var colLineId            = reader.GetOrdinal("inbound_line_id");
        var colInboundRef        = reader.GetOrdinal("inbound_ref");
        var colHeaderStatus      = reader.GetOrdinal("header_status");
        var colLineState         = reader.GetOrdinal("line_state");
        var colSkuCode           = reader.GetOrdinal("sku_code");
        var colSkuDesc           = reader.GetOrdinal("sku_description");
        var colExpectedUnitQty   = reader.GetOrdinal("expected_unit_qty");
        var colLineExpectedQty   = reader.GetOrdinal("line_expected_qty");
        var colLineReceivedQty   = reader.GetOrdinal("line_received_qty");
        var colOutstandingBefore = reader.GetOrdinal("outstanding_before");
        var colOutstandingAfter  = reader.GetOrdinal("outstanding_after");
        var colBatchNumber       = reader.GetOrdinal("batch_number");
        var colBestBefore        = reader.GetOrdinal("best_before_date");
        var colClaimExpiresAt    = reader.GetOrdinal("claim_expires_at");
        var colClaimToken        = reader.GetOrdinal("claim_token");
        var colArrivalStatus     = reader.GetOrdinal("arrival_stock_status_code");

        var success = reader.GetBoolean(colSuccess);
        var code    = reader.IsDBNull(colCode) ? "ERRSSCC99" : reader.GetString(colCode);

        return new SsccValidationDto
        {
            Success         = success,
            ResultCode      = code,
            FriendlyMessage = _resolver.Resolve(code),

            InboundExpectedUnitId  = reader.IsDBNull(colExpectedUnitId) ? 0 : reader.GetInt32(colExpectedUnitId),
            InboundLineId          = reader.IsDBNull(colLineId) ? 0 : reader.GetInt32(colLineId),
            InboundRef             = reader.IsDBNull(colInboundRef) ? "" : reader.GetString(colInboundRef),
            HeaderStatus           = reader.IsDBNull(colHeaderStatus) ? "" : reader.GetString(colHeaderStatus),
            LineState              = reader.IsDBNull(colLineState) ? "" : reader.GetString(colLineState),

            SkuCode                = reader.IsDBNull(colSkuCode) ? "" : reader.GetString(colSkuCode),
            SkuDescription         = reader.IsDBNull(colSkuDesc) ? "" : reader.GetString(colSkuDesc),

            ExpectedUnitQty        = reader.IsDBNull(colExpectedUnitQty) ? 0 : reader.GetInt32(colExpectedUnitQty),
            LineExpectedQty        = reader.IsDBNull(colLineExpectedQty) ? 0 : reader.GetInt32(colLineExpectedQty),
            LineReceivedQty        = reader.IsDBNull(colLineReceivedQty) ? 0 : reader.GetInt32(colLineReceivedQty),

            OutstandingBefore      = reader.IsDBNull(colOutstandingBefore) ? 0 : reader.GetInt32(colOutstandingBefore),
            OutstandingAfter       = reader.IsDBNull(colOutstandingAfter) ? 0 : reader.GetInt32(colOutstandingAfter),

            BatchNumber            = reader.IsDBNull(colBatchNumber) ? null : reader.GetString(colBatchNumber),
            BestBeforeDate         = reader.IsDBNull(colBestBefore) ? null : reader.GetDateTime(colBestBefore),

            ClaimExpiresAt         = reader.IsDBNull(colClaimExpiresAt) ? null : reader.GetDateTime(colClaimExpiresAt),
            ClaimToken             = reader.IsDBNull(colClaimToken) ? null : reader.GetGuid(colClaimToken),
            ArrivalStockStatusCode = reader.IsDBNull(colArrivalStatus) ? "AV" : reader.GetString(colArrivalStatus)
        };
    }
}
