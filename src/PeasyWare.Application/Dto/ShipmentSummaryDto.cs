namespace PeasyWare.Application.Dto;

public sealed class ShipmentSummaryDto
{
    public int    ShipmentId      { get; init; }
    public string ShipmentRef     { get; init; } = string.Empty;
    public string ShipmentStatus  { get; init; } = string.Empty;
    public string? VehicleRef     { get; init; }
    public string? HaulierName    { get; init; }
    public string? PlannedDeparture { get; init; }
    public int    TotalOrders     { get; init; }
    public int    OrdersPicked    { get; init; }
    public int    OrdersLoaded    { get; init; }
}
