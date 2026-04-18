namespace PeasyWare.Application.Dto;

public sealed class OutboundAllocationDto
{
    public int    AllocationId      { get; init; }
    public int    OutboundLineId    { get; init; }
    public int    LineNo            { get; init; }
    public string SkuCode           { get; init; } = string.Empty;
    public string SkuDescription    { get; init; } = string.Empty;
    public int    AllocatedQty      { get; init; }
    public int    OrderedQty        { get; init; }
    public string AllocationStatus  { get; init; } = string.Empty;
    public string Sscc              { get; init; } = string.Empty;
    public string SourceBinCode     { get; init; } = string.Empty;
    public string? BatchNumber      { get; init; }
    public string? BestBeforeDate   { get; init; }
}
