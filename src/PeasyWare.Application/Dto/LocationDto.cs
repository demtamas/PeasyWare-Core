namespace PeasyWare.Application.Dto;

public sealed class LocationDto
{
    public int      BinId             { get; init; }
    public string   BinCode           { get; init; } = string.Empty;
    public string   StorageTypeCode   { get; init; } = string.Empty;
    public string?  StorageTypeName   { get; init; }
    public string?  SectionCode       { get; init; }
    public string?  ZoneCode          { get; init; }
    public string?  ZoneName          { get; init; }
    public int      Capacity          { get; init; }
    public bool     IsActive          { get; init; }
    public bool     IsLocked          { get; init; }
    public string?  LockedReason      { get; init; }
    public string?  LockedByUsername  { get; init; }
    public DateTime? LockedAt         { get; init; }
    public string?  Notes             { get; init; }

    // Stock summary
    public int      UnitCount         { get; init; }
    public int      TotalQty          { get; init; }

    // Single-unit convenience (populated only when UnitCount == 1)
    public string?  Sscc              { get; init; }
    public string?  SkuCode           { get; init; }
    public string?  SkuDescription    { get; init; }
    public string?  BatchNumber       { get; init; }
    public DateTime? BestBeforeDate   { get; init; }
    public string?  StockState        { get; init; }
    public string?  StockStatus       { get; init; }
}
