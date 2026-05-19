namespace PeasyWare.Application.Dto;

public sealed class ActiveInventoryDto
{
    public string    Sscc             { get; init; } = string.Empty;
    public string    SkuCode          { get; init; } = string.Empty;
    public string    SkuDescription   { get; init; } = string.Empty;
    public string?   BatchNumber      { get; init; }
    public DateOnly? BestBeforeDate   { get; init; }
    public int       Quantity         { get; init; }
    public string    StockState       { get; init; } = string.Empty;
    public string    StockStatus      { get; init; } = string.Empty;
    public string    BinCode          { get; init; } = string.Empty;
    public string?   ZoneCode         { get; init; }
    public string?   StorageTypeCode  { get; init; }
    public DateTime  ReceivedAt       { get; init; }
    public string?   ReceivedBy       { get; init; }
    public string?   LastMovementType { get; init; }
    public DateTime? LastMovementAt   { get; init; }
    public string?   LastMovedBy      { get; init; }

    /// <summary>
    /// The inbound delivery reference this unit arrived on.
    /// Populated from the most recent non-reversal inbound receipt.
    /// </summary>
    public string?   InboundRef       { get; init; }

    /// <summary>
    /// The outbound order reference if this unit is currently allocated.
    /// NULL when the unit is not allocated (available, on hold, etc.).
    /// </summary>
    public string?   OrderRef         { get; init; }

    /// <summary>
    /// Current allocation status (PENDING, CONFIRMED, PICKED) if allocated.
    /// NULL when not allocated.
    /// </summary>
    public string?   AllocationStatus { get; init; }

    /// <summary>
    /// Username of the operator who allocated this unit.
    /// </summary>
    public string?   AllocatedBy      { get; init; }

    /// <summary>
    /// When the allocation was created.
    /// </summary>
    public DateTime? AllocatedAt      { get; init; }

    /// <summary>
    /// Single reference column for the grid:
    /// shows OrderRef when allocated, InboundRef otherwise.
    /// </summary>
    public string?   Reference        => OrderRef ?? InboundRef;
}
