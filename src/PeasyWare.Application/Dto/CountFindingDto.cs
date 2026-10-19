namespace PeasyWare.Application.Dto;

/// <summary>
/// One thing a count found, and what was done about it (warehouse.v_count_findings).
///
/// Empty-bin counts: a pallet found in a bin the system believed was empty.
/// FindingCode is RECORD_CORRECTED, UNKNOWN_UNIT or NOT_CORRECTED; for
/// NOT_CORRECTED, ReasonCode / ReasonMessage say which rule stopped the
/// correction.
///
/// Bin counts: a difference between what was counted and what the system holds.
/// FindingCode adds QTY_DIFFERENCE (CountedQty vs SystemQty), MISSING (the system
/// has it here, nobody scanned it) and MISPLACED (scanned here, recorded in
/// PreviousBinCode). The count never changes a stock record: each of those three
/// waits for someone with counts.adjust, who applies it or declines it
/// (ResolutionCode APPLIED / DECLINED, with ResolutionNote; ResolutionMovementId
/// is the ledger row an apply wrote).
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

    public int?       CountedQty        { get; init; }
    public int?       SystemQty         { get; init; }

    public string?    ResolutionCode    { get; init; }
    public DateTime?  ResolvedAt        { get; init; }
    public string?    ResolvedBy        { get; init; }
    public string?    ResolutionNote    { get; init; }
    public int?       ResolutionMovementId { get; init; }

    public string?    ShipmentRef       { get; init; }
    public string?    VehicleRef        { get; init; }
    public DateTime?  ShippedAt         { get; init; }
    public string?    OrderRef          { get; init; }
    public string?    CustomerName      { get; init; }

    /// <summary>A person with counts.adjust has applied or declined it.</summary>
    public bool IsResolved => ResolutionCode is not null;

    /// <summary>
    /// A kind of finding that can be applied (the stock record changed to match the
    /// count). Unknown and shipped / reversed pallets have nothing to apply; they can
    /// only be declined, which acknowledges them.
    /// </summary>
    public bool IsActionable =>
        FindingCode is "QTY_DIFFERENCE" or "MISSING" or "MISPLACED";

    /// <summary>True for findings a person still needs to look at.</summary>
    public bool NeedsReview =>
        FindingCode != "RECORD_CORRECTED" && !IsResolved;
}
