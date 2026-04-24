namespace PeasyWare.API.Responses;

public sealed class OrderCreatedResponse
{
    public int    OutboundOrderId { get; init; }
    public string OrderRef        { get; init; } = null!;
}

public sealed class ShipmentCreatedResponse
{
    public int    ShipmentId  { get; init; }
    public string ShipmentRef { get; init; } = null!;
}
