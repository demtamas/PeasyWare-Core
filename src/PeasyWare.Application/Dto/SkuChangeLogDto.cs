namespace PeasyWare.Application.Dto;

public sealed class SkuChangeLogDto
{
    public long      TraceId            { get; init; }
    public DateTime  OccurredAt         { get; init; }
    public string?   Username           { get; init; }
    public string    ActionType         { get; init; } = null!; // INSERT / UPDATE
    public string?   SkuCode            { get; init; }

    // Before
    public string?   DescBefore         { get; init; }
    public string?   EanBefore          { get; init; }
    public string?   UomBefore          { get; init; }
    public decimal?  WeightBefore       { get; init; }
    public int?      HuQtyBefore        { get; init; }
    public bool?     BatchReqBefore     { get; init; }
    public bool?     FullHuReqBefore    { get; init; }
    public bool?     HazardousBefore    { get; init; }
    public bool?     ActiveBefore       { get; init; }
    public string?   StorageBefore      { get; init; }
    public string?   SectionBefore      { get; init; }

    // After
    public string?   DescAfter          { get; init; }
    public string?   EanAfter           { get; init; }
    public string?   UomAfter           { get; init; }
    public decimal?  WeightAfter        { get; init; }
    public int?      HuQtyAfter         { get; init; }
    public bool?     BatchReqAfter      { get; init; }
    public bool?     FullHuReqAfter     { get; init; }
    public bool?     HazardousAfter     { get; init; }
    public bool?     ActiveAfter        { get; init; }
    public string?   StorageAfter       { get; init; }
    public string?   SectionAfter       { get; init; }
}
