namespace PeasyWare.Application.Dto;

public sealed class OrderLineDto
{
    public int       LineNo         { get; init; }
    public string    SkuCode        { get; init; } = null!;
    public int       OrderedQty     { get; init; }
    public string?   RequestedBatch { get; init; }
    public DateTime? RequestedBbe   { get; init; }
    public string?   Notes          { get; init; }
}
