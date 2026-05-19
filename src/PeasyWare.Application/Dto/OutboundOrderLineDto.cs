namespace PeasyWare.Application.Dto;

public sealed class OutboundOrderLineDto
{
    public int OutboundLineId { get; init; }
    public int LineNo { get; init; }
    public string SkuCode { get; init; } = string.Empty;
    public string SkuDescription { get; init; } = string.Empty;
    public int OrderedQty { get; init; }
    public int AllocatedQty { get; init; }
    public int PickedQty { get; init; }
    public string LineStatusCode { get; init; } = string.Empty;
    public string? RequestedBatch { get; init; }
    public string? RequestedBbe { get; init; }
    public string? Notes { get; init; }
}
