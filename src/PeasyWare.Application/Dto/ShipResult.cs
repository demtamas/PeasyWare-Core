namespace PeasyWare.Application.Dto;

public sealed class ShipResult
{
    public bool   Success         { get; init; }
    public string ResultCode      { get; init; } = string.Empty;
    public string FriendlyMessage { get; init; } = string.Empty;
    public int    UnitsShipped    { get; init; }
}
