using Microsoft.AspNetCore.Mvc;
using PeasyWare.API.Requests;
using PeasyWare.API.Responses;
using PeasyWare.Infrastructure.Bootstrap;

namespace PeasyWare.API.Controllers;

[ApiController]
[Route("api/inbound")]
public sealed class InboundController : ControllerBase
{
    private readonly AppRuntime _runtime;

    public InboundController(AppRuntime runtime) => _runtime = runtime;

    /// <summary>Creates a new inbound delivery header.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(ApiResponse<InboundCreatedResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),                         409)]
    [ProducesResponseType(typeof(ApiResponse),                         400)]
    public IActionResult Create([FromBody] CreateInboundRequest request)
    {
        var repo   = _runtime.Repositories.CreateInboundCommand();
        var result = repo.CreateInbound(
            inboundRef:        request.InboundRef,
            supplierPartyCode: request.SupplierPartyCode,
            haulierPartyCode:  request.HaulierPartyCode,
            expectedArrivalAt: request.ExpectedArrivalAt);

        if (!result.Success)
        {
            var status = result.ResultCode == "ERRINB02" ? 409 : 400;
            return StatusCode(status, ApiResponse.Fail(result.ResultCode, result.FriendlyMessage));
        }

        return Ok(ApiResponse<InboundCreatedResponse>.Ok(
            result.ResultCode,
            result.FriendlyMessage,
            new InboundCreatedResponse
            {
                InboundId  = result.EntityId,
                InboundRef = request.InboundRef
            }));
    }

    /// <summary>Adds a line to an existing inbound delivery.</summary>
    [HttpPost("{inboundRef}/lines")]
    [ProducesResponseType(typeof(ApiResponse<InboundLineCreatedResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),                             404)]
    [ProducesResponseType(typeof(ApiResponse),                             400)]
    public IActionResult AddLine(string inboundRef, [FromBody] AddInboundLineRequest request)
    {
        var repo   = _runtime.Repositories.CreateInboundCommand();
        var result = repo.AddInboundLine(
            inboundRef:         inboundRef,
            skuCode:            request.SkuCode,
            expectedQty:        request.ExpectedQty,
            batchNumber:        request.BatchNumber,
            bestBeforeDate:     request.BestBeforeDate.HasValue
                                    ? request.BestBeforeDate.Value.ToDateTime(TimeOnly.MinValue)
                                    : null,
            arrivalStockStatus: request.ArrivalStockStatus);

        if (!result.Success)
        {
            var status = result.ResultCode == "ERRINBL01" ? 404 : 400;
            return StatusCode(status, ApiResponse.Fail(result.ResultCode, result.FriendlyMessage));
        }

        return Ok(ApiResponse<InboundLineCreatedResponse>.Ok(
            result.ResultCode,
            result.FriendlyMessage,
            new InboundLineCreatedResponse
            {
                InboundLineId = result.EntityId,
                InboundId     = result.ParentId
            }));
    }

    /// <summary>
    /// Adds expected SSCC units to an inbound line.
    /// SSCCs normalised to 18-digit canonical form automatically.
    /// Accepts raw 18-digit or scanner format (00 + 18 digits).
    /// </summary>
    [HttpPost("{inboundRef}/units")]
    [ProducesResponseType(typeof(ApiResponse<ExpectedUnitsCreatedResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse),                               404)]
    [ProducesResponseType(typeof(ApiResponse),                               400)]
    public IActionResult AddExpectedUnits(
        string inboundRef,
        [FromBody] AddExpectedUnitsRequest request)
    {
        var repo    = _runtime.Repositories.CreateInboundCommand();
        var created = 0;
        var skipped = 0;

        foreach (var unit in request.Units)
        {
            var sscc = NormaliseSscc(unit.Sscc);

            if (sscc is null) { skipped++; continue; }

            var result = repo.AddExpectedUnit(
                inboundRef:     inboundRef,
                sscc:           sscc,
                quantity:       unit.Quantity,
                batchNumber:    unit.BatchNumber,
                bestBeforeDate: unit.BestBeforeDate.HasValue
                                    ? unit.BestBeforeDate.Value.ToDateTime(TimeOnly.MinValue)
                                    : null);

            if (result.Success) created++;
            else                skipped++;
        }

        return Ok(ApiResponse<ExpectedUnitsCreatedResponse>.Ok(
            "SUCINBU01",
            $"{created} unit(s) created, {skipped} skipped.",
            new ExpectedUnitsCreatedResponse
            {
                UnitsCreated = created,
                UnitsSkipped = skipped
            }));
    }

    // ── SSCC normalisation ────────────────────────────────────────────────
    // 20 chars starting with "00" → strip AI prefix → 18 digits
    // < 18 chars, all digits      → left-pad to 18
    // exactly 18 chars            → use as-is
    // anything else               → reject (null)

    private static string? NormaliseSscc(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;

        input = input.Trim();

        if (input.Length == 20 && input.StartsWith("00"))
            input = input[2..];

        if (!input.All(char.IsDigit)) return null;

        if (input.Length < 18)  input = input.PadLeft(18, '0');
        if (input.Length != 18) return null;

        return input;
    }
}
