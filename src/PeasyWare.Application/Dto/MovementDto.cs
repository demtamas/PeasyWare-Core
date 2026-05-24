namespace PeasyWare.Application.Dto;

public sealed class MovementDto
{
    public int       MovementId        { get; init; }
    public DateTime  MovedAt           { get; init; }
    public string    MovedBy           { get; init; } = string.Empty;
    public string    Sscc              { get; init; } = string.Empty;
    public string    SkuCode           { get; init; } = string.Empty;
    public string    SkuDescription    { get; init; } = string.Empty;
    public int       MovedQty          { get; init; }
    public string?   FromBin           { get; init; }
    public string?   ToBin             { get; init; }
    public string?   FromState         { get; init; }
    public string?   ToState           { get; init; }
    public string?   FromStatus        { get; init; }
    public string?   ToStatus          { get; init; }
    public string    MovementType      { get; init; } = string.Empty;
    public string?   ReferenceType     { get; init; }
    public string?   ReferenceRef      { get; init; }
    public bool      IsReversal        { get; init; }
}
