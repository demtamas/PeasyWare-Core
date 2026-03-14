using System.Data;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class SqlInboundQueryRepository : IInboundQueryRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly Guid _sessionId;
    private readonly int _userId;
    private readonly IErrorMessageResolver _errorMessageResolver;

    public SqlInboundQueryRepository(
        SqlConnectionFactory factory,
        Guid sessionId,
        int userId,
        IErrorMessageResolver errorMessageResolver)
    {
        _factory = factory ?? throw new ArgumentNullException(nameof(factory));
        _sessionId = sessionId;
        _userId = userId;
        _errorMessageResolver = errorMessageResolver
            ?? throw new ArgumentNullException(nameof(errorMessageResolver));
    }

    // ------------------------------------------------------------
    // Activatable inbounds
    // ------------------------------------------------------------

    public IEnumerable<ActivatableInboundDto> GetActivatableInbounds()
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandType = CommandType.Text;
        command.CommandText = @"
            SELECT inbound_id,
                   inbound_ref,
                   expected_arrival_at,
                   line_count
            FROM deliveries.vw_inbounds_activatable
            ORDER BY expected_arrival_at, inbound_ref;";

        using var reader = command.ExecuteReader();

        while (reader.Read())
        {
            yield return new ActivatableInboundDto
            {
                InboundId = reader.GetInt32(0),
                InboundRef = reader.GetString(1),
                ExpectedArrivalAt =
                    reader.IsDBNull(2)
                        ? null
                        : reader.GetDateTime(2),
                LineCount = reader.GetInt32(3)
            };
        }
    }

    // ------------------------------------------------------------
    // Receivable lines (manual mode support)
    // ------------------------------------------------------------

    public IEnumerable<InboundLineDto> GetReceivableLines(string inboundRef)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandType = CommandType.Text;
        command.CommandText = @"
            SELECT inbound_line_id,
                   line_no,
                   sku_code,
                   sku_description,
                   expected_qty,
                   received_qty,
                   outstanding_qty
            FROM deliveries.vw_inbound_lines_receivable
            WHERE inbound_ref = @ref
            ORDER BY line_no;";

        command.Parameters.AddWithValue("@inbound_ref", inboundRef);

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
    // Inbound summary (lifecycle + SSCC presence)
    // ------------------------------------------------------------

    public InboundSummaryDto GetInboundSummary(string inboundRef)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "deliveries.usp_get_inbound_summary";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@inbound_ref", inboundRef);

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
    // Outstanding SSCC count (truth source for loop)
    // ------------------------------------------------------------

    public int GetOutstandingSsccCount(string inboundRef)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandType = CommandType.Text;
        command.CommandText = @"
            SELECT COUNT(1)
            FROM deliveries.inbound_expected_units eu
            JOIN deliveries.inbound_lines l
                ON eu.inbound_line_id = l.inbound_line_id
            JOIN deliveries.inbound_deliveries d
                ON l.inbound_id = d.inbound_id
            WHERE d.inbound_ref = @inbound_ref
              AND eu.received_inventory_unit_id IS NULL;";

        command.Parameters.AddWithValue("@inbound_ref", inboundRef);

        var result = command.ExecuteScalar();

        return result == null ? 0 : Convert.ToInt32(result);
    }

    public SsccValidationDto ValidateSsccForInbound(
    string externalRef,
    string stagingBin)
    {
        using var connection =
            _factory.CreateForCommand(_sessionId, _userId);

        using var command = connection.CreateCommand();
        command.CommandText = "deliveries.usp_validate_sscc_for_receive";
        command.CommandType = CommandType.StoredProcedure;

        command.Parameters.AddWithValue("@external_ref", externalRef);
        command.Parameters.AddWithValue("@staging_bin_code", stagingBin);
        command.Parameters.AddWithValue("@user_id", _userId);
        command.Parameters.AddWithValue("@session_id", _sessionId);

        using var reader = command.ExecuteReader();

        if (!reader.Read())
        {
            const string code = "ERRSSCC99";
            var friendly = _errorMessageResolver.Resolve(code);

            return new SsccValidationDto
            {
                Success = false,
                ResultCode = code,
                FriendlyMessage = friendly
            };
        }

        // Column layout (must match SP exactly):
        // 0  success
        // 1  result_code
        // 2  inbound_expected_unit_id
        // 3  inbound_line_id
        // 4  inbound_ref
        // 5  header_status
        // 6  line_state
        // 7  sku_code
        // 8  sku_description
        // 9  expected_unit_qty
        // 10 line_expected_qty
        // 11 line_received_qty
        // 12 outstanding_before
        // 13 outstanding_after
        // 14 batch_number
        // 15 best_before_date
        // 16 claimed_session_id
        // 17 claimed_by_user_id
        // 18 claim_expires_at
        // 19 claim_token

        var success = reader.GetBoolean(0);
        var resultCode = reader.IsDBNull(1) ? "ERRSSCC99" : reader.GetString(1);
        var friendlyMessage = _errorMessageResolver.Resolve(resultCode);

        // 🔍 DEV SQL Debug Hook
        if (!success && resultCode == "ERRSSCC99")
        {
            if (reader.FieldCount >= 23)
            {
                int? errNo = reader.IsDBNull(20) ? null : reader.GetInt32(20);
                int? errLine = reader.IsDBNull(21) ? null : reader.GetInt32(21);
                string? errMsg = reader.IsDBNull(22) ? null : reader.GetString(22);

                Console.WriteLine($"SQL DEBUG -> {errNo} at line {errLine}: {errMsg}");
            }
        }

        return new SsccValidationDto
        {
            Success = success,
            ResultCode = resultCode,
            FriendlyMessage = friendlyMessage,

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
            ClaimToken = reader.IsDBNull(19) ? null : reader.GetGuid(19)
        };
    }
}
