namespace PeasyWare.Application.Dto;

public sealed class ActivatableInboundDto
{
    public int InboundId { get; init; }
    public string InboundRef { get; init; } = "";
    public DateTime? ExpectedArrivalAt { get; init; }
    public int LineCount { get; init; }
}
