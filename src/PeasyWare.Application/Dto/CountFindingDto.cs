namespace PeasyWare.Application.Dto;

/// <summary>
/// A pallet found in a bin the system believed was empty, and what was done
/// about it (warehouse.v_count_findings). FindingCode is RECORD_CORRECTED,
/// UNKNOWN_UNIT or NOT_CORRECTED; for NOT_CORRECTED, ReasonCode / ReasonMessage
/// say which rule stopped the correction.
///
/// ShipmentRef / ShippedAt / VehicleRef say which delivery a shipped pallet left
/// on; OrderRef / CustomerName say which order it was picked for. All null for a
/// pallet that was never on an order.
/// </summary>
public sealed class CountFindingDto
{
    public int        FindingId         { get; init; }
    public int        CountId           { get; init; }
    public string     BinCode           { get; init; } = string.Empty;
    public string     ScannedRef        { get; init; } = string.Empty;
    public int?       InventoryUnitId   { get; init; }
    public string?    SkuCode           { get; init; }
    public string     FindingCode       { get; init; } = string.Empty;
    public string?    ReasonCode        { get; init; }
    public string?    ReasonMessage     { get; init; }
    public string?    PreviousBinCode   { get; init; }
    public int?       MovementId        { get; init; }
    public DateTime   FoundAt           { get; init; }
    public string?    FoundBy           { get; init; }

    public string?    ShipmentRef       { get; init; }
    public string?    VehicleRef        { get; init; }
    public DateTime?  ShippedAt         { get; init; }
    public string?    OrderRef          { get; init; }
    public string?    CustomerName      { get; init; }

    /// <summary>True for findings a person still needs to look at.</summary>
    public bool NeedsReview => FindingCode != "RECORD_CORRECTED";
}
