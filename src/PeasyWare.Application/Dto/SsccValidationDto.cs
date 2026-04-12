namespace PeasyWare.Application.Dto;

public sealed class SsccValidationDto
{
    public bool Success { get; set; }
    public string ResultCode { get; set; } = "";     // ✅ NEW
    public string FriendlyMessage { get; set; } = "";

    public int InboundExpectedUnitId { get; set; }   // ✅ NEW (non-null in success)
    public int InboundLineId { get; set; }
    public string InboundRef { get; set; } = "";
    public string HeaderStatus { get; set; } = "";
    public string LineState { get; set; } = "";

    public string SkuCode { get; set; } = "";
    public string SkuDescription { get; set; } = "";

    public int ExpectedUnitQty { get; set; }
    public int LineExpectedQty { get; set; }
    public int LineReceivedQty { get; set; }
    public string ArrivalStockStatusCode { get; set; } = "AV";

    public int OutstandingBefore { get; set; }
    public int OutstandingAfter { get; set; }

    public string? BatchNumber { get; set; }
    public DateTime? BestBeforeDate { get; set; }

    public Guid? ClaimToken { get; set; }
    public DateTime? ClaimExpiresAt { get; set; }
}