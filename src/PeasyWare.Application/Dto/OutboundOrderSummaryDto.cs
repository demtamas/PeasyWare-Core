namespace PeasyWare.Application.Dto;

public sealed class OutboundOrderSummaryDto
{
    public int    OutboundOrderId  { get; init; }
    public string OrderRef         { get; init; } = string.Empty;
    public string OrderStatusCode  { get; init; } = string.Empty;
    public string CustomerName     { get; init; } = string.Empty;
    public string? RequiredDate    { get; init; }
    public int    TotalLines       { get; init; }
    public int    TotalAllocated   { get; init; }
    public int    TotalOrdered     { get; init; }
}
