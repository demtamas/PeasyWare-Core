namespace PeasyWare.Application.Dto;

public sealed class ShipmentManifestDto
{
    public string   ShipmentRef       { get; init; } = string.Empty;
    public string   ShipmentStatus    { get; init; } = string.Empty;
    public string?  VehicleRef        { get; init; }
    public string?  HaulierName       { get; init; }
    public string?  CustomerName      { get; init; }
    public string?  DeliveryLine1     { get; init; }
    public string?  DeliveryCity      { get; init; }
    public string?  DeliveryPostalCode{ get; init; }
    public string?  DeliveryCountry   { get; init; }
    public DateTime? ActualDeparture  { get; init; }
    public int      TotalPallets      { get; init; }
    public int      TotalUnits        { get; init; }
    public decimal  TotalWeightKg     { get; init; }

    public IReadOnlyList<ShipmentManifestLineDto> Lines { get; init; } = [];
}

public sealed class ShipmentManifestLineDto
{
    public string   Sscc          { get; init; } = string.Empty;
    public string   SkuCode       { get; init; } = string.Empty;
    public string   SkuDescription{ get; init; } = string.Empty;
    public string?  BatchNumber   { get; init; }
    public string?  BestBefore    { get; init; }
    public int      Quantity      { get; init; }
    public string?  UomCode       { get; init; }
    public decimal? WeightPerUnit { get; init; }  // grams
    public decimal? TotalWeightKg { get; init; }
    public string?  OrderRef      { get; init; }
    public string?  PickedFromBin { get; init; }
}
