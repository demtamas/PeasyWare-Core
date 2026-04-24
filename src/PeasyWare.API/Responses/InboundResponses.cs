namespace PeasyWare.API.Responses;

public sealed class InboundCreatedResponse
{
    public int    InboundId  { get; init; }
    public string InboundRef { get; init; } = null!;
}

public sealed class InboundLineCreatedResponse
{
    public int InboundLineId { get; init; }
    public int InboundId     { get; init; }
}

public sealed class ExpectedUnitsCreatedResponse
{
    public int UnitsCreated { get; init; }
    public int UnitsSkipped { get; init; }
}
