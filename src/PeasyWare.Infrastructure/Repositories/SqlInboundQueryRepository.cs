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

        while (reader.Read())
        {
            yield return new ActivatableInboundDto
            {
                InboundId = reader.GetInt32(0),
                InboundRef = reader.GetString(1),
                ExpectedArrivalAt = reader.IsDBNull(2) ? null : reader.GetDateTime(2),
                LineCount = reader.GetInt32(3)
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

        while (reader.Read())
        {
            yield return new InboundLineDto
            {
                InboundLineId = reader.GetInt32(0),
                LineNo = reader.GetInt32(1),
                SkuCode = reader.GetString(2),
                Description = reader.GetString(3),
                ExpectedQty = reader.GetInt32(4),
                ReceivedQty = reader.GetInt32(5),
                OutstandingQty = reader.GetInt32(6)
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

        return new InboundSummaryDto
        {
            Exists = reader.GetBoolean(0),
            IsReceivable = reader.GetBoolean(1),
            HasExpectedUnits = reader.GetBoolean(2)
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
    // SSCC validation
    // ------------------------------------------------------------

    public SsccValidationDto ValidateSsccForInbound(
        string externalRef,
        string stagingBin)
    {
        using var connection = _factory.CreateForCommand(_session);
        using var command = connection.CreateCommand();

        command.CommandText = "deliveries.usp_validate_sscc_for_receive";
        command.Parameters.AddWithValue("@user_id", _session.UserId);
        command.Parameters.AddWithValue("@session_id", _session.SessionId);
        command.CommandType = CommandType.StoredProcedure;

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

        var success = reader.GetBoolean(0);
        var code = reader.IsDBNull(1) ? "ERRSSCC99" : reader.GetString(1);

        return new SsccValidationDto
        {
            Success = success,
            ResultCode = code,
            FriendlyMessage = _resolver.Resolve(code),

            InboundExpectedUnitId = reader.IsDBNull(2) ? 0 : reader.GetInt32(2),
            InboundLineId = reader.IsDBNull(3) ? 0 : reader.GetInt32(3),
            InboundRef = reader.IsDBNull(4) ? "" : reader.GetString(4),
            HeaderStatus = reader.IsDBNull(5) ? "" : reader.GetString(5),
            LineState = reader.IsDBNull(6) ? "" : reader.GetString(6),

            SkuCode = reader.IsDBNull(7) ? "" : reader.GetString(7),
            SkuDescription = reader.IsDBNull(8) ? "" : reader.GetString(8),

            ExpectedUnitQty = reader.IsDBNull(9) ? 0 : reader.GetInt32(9),
            LineExpectedQty = reader.IsDBNull(10) ? 0 : reader.GetInt32(10),
            LineReceivedQty = reader.IsDBNull(11) ? 0 : reader.GetInt32(11),

            OutstandingBefore = reader.IsDBNull(12) ? 0 : reader.GetInt32(12),
            OutstandingAfter = reader.IsDBNull(13) ? 0 : reader.GetInt32(13),

            BatchNumber = reader.IsDBNull(14) ? null : reader.GetString(14),
            BestBeforeDate = reader.IsDBNull(15) ? null : reader.GetDateTime(15),

            ClaimExpiresAt = reader.IsDBNull(18) ? null : reader.GetDateTime(18),
            ClaimToken = reader.IsDBNull(19) ? null : reader.GetGuid(19),
            ArrivalStockStatusCode = reader.IsDBNull(20) ? "AV" : reader.GetString(20)
        };
    }
}