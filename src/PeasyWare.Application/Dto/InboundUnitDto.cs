namespace PeasyWare.Application.Dto;

/// <summary>
/// Expected or received unit on an inbound line — SSCC level.
/// </summary>
public sealed class InboundUnitDto
{
    public int      ExpectedUnitId    { get; init; }
    public string   Sscc              { get; init; } = string.Empty;
    public string?  BatchNumber       { get; init; }
    public string?  BestBeforeDate    { get; init; }
    public int      Quantity          { get; init; }
    public string   UnitStatus        { get; init; } = string.Empty;  // OUTSTANDING / RECEIVED / REVERSED
    public string?  ReceivedAt        { get; init; }
    public string?  ReceivedBin       { get; init; }
    public string?  ReceivedBy        { get; init; }
}
