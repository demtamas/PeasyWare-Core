namespace PeasyWare.Application.Dto;

public sealed class InboundReceiptDto
{
    public int ReceiptId { get; init; }
    public int InboundLineId { get; init; }
    public int? InboundExpectedUnitId { get; init; }
    public int InventoryUnitId { get; init; }
    public string? ExternalRef { get; init; }
    public int ReceivedQty { get; init; }
    public DateTime ReceivedAt { get; init; }
    public bool IsReversal { get; init; }
    public int? ReversedReceiptId { get; init; }
    public string StockStateCode { get; init; } = "";
    public string? CurrentBinCode { get; init; }
    public string InboundRef { get; init; } = "";
    public string LineStateCode { get; init; } = "";
}
