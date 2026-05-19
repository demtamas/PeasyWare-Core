namespace PeasyWare.Application.Dto;

public sealed class WarehouseTaskDto
{
    public int       TaskId          { get; init; }
    public string    TaskTypeCode    { get; init; } = "";
    public string    TaskState       { get; init; } = "";
    public string    TaskStateCode   { get; init; } = "";
    public bool      IsTerminal      { get; init; }

    public string    Sscc            { get; init; } = "";
    public string    SkuCode         { get; init; } = "";
    public string    SkuDescription  { get; init; } = "";
    public int       Quantity        { get; init; }
    public string?   BatchNumber     { get; init; }

    public string?   SourceBin       { get; init; }
    public string?   DestinationBin  { get; init; }

    public string?   ClaimedBy       { get; init; }
    public DateTime? ClaimedAt       { get; init; }
    public DateTime? ExpiresAt       { get; init; }

    public string?   CompletedBy     { get; init; }
    public DateTime? CompletedAt     { get; init; }

    public string?   CreatedBy       { get; init; }
    public DateTime  CreatedAt       { get; init; }
    public DateTime? UpdatedAt       { get; init; }
}
