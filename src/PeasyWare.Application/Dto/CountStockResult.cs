namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of reporting a pallet found in a bin the system believed was empty.
/// FindingCode is RECORD_CORRECTED, UNKNOWN_UNIT or NOT_CORRECTED (null when
/// nothing was recorded). For NOT_CORRECTED, ReasonCode / ReasonMessage say
/// which rule stopped the correction.
///
/// For a pallet the system knows left the building, ShipmentRef / ShippedAt /
/// VehicleRef say which delivery it left on; OrderRef / CustomerName say which
/// order it was picked for (also set for a picked pallet that has not shipped).
/// All null for a pallet that was never on an order.
/// </summary>
public sealed class CountStockResult
{
    public bool      Success           { get; init; }
    public string    ResultCode        { get; init; } = string.Empty;
    public string    FriendlyMessage   { get; init; } = string.Empty;
    public string?   FindingCode       { get; init; }
    public int       CountId           { get; init; }
    public int?      InventoryUnitId   { get; init; }
    public string?   SkuCode           { get; init; }
    public string?   PreviousBinCode   { get; init; }
    public int       PendingBins       { get; init; }
    public string?   ReasonCode        { get; init; }
    public string?   ReasonMessage     { get; init; }

    public string?   ShipmentRef       { get; init; }
    public string?   VehicleRef        { get; init; }
    public DateTime? ShippedAt         { get; init; }
    public string?   OrderRef          { get; init; }
    public string?   CustomerName      { get; init; }

    public bool IsWarning =>
        ResultCode.StartsWith("WARN", StringComparison.OrdinalIgnoreCase);
}
