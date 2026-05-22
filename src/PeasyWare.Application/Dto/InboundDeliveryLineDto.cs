namespace PeasyWare.Application.Dto;

/// <summary>
/// Inbound delivery line with full progress — used by the Desktop line drill-down.
/// </summary>
public sealed class InboundDeliveryLineDto
{
    public int      InboundLineId     { get; init; }
    public int      LineNo            { get; init; }
    public string   SkuCode           { get; init; } = string.Empty;
    public string   SkuDescription    { get; init; } = string.Empty;
    public string?  BatchNumber       { get; init; }
    public string?  BestBeforeDate    { get; init; }
    public string   LineStatusCode    { get; init; } = string.Empty;
    public int      ExpectedQty       { get; init; }
    public int      ReceivedQty       { get; init; }
    public int      OutstandingQty    { get; init; }
    public int      UnitCount         { get; init; }   // expected SSCCs on this line
}
