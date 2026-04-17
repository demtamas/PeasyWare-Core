namespace PeasyWare.Application.Dto;

public sealed class ActiveInventoryDto
{
    public string  Sscc              { get; init; } = string.Empty;
    public string  SkuCode           { get; init; } = string.Empty;
    public string  SkuDescription    { get; init; } = string.Empty;
    public string? BatchNumber       { get; init; }
    public DateOnly? BestBeforeDate  { get; init; }
    public int     Quantity          { get; init; }
    public string  StockState        { get; init; } = string.Empty;
    public string  StockStatus       { get; init; } = string.Empty;
    public string  BinCode           { get; init; } = string.Empty;
    public string? ZoneCode          { get; init; }
    public string? StorageTypeCode   { get; init; }
    public DateTime ReceivedAt       { get; init; }
    public string?  ReceivedBy       { get; init; }
    public string?  LastMovementType { get; init; }
    public DateTime? LastMovementAt  { get; init; }
    public string?  LastMovedBy      { get; init; }
}
