namespace PeasyWare.Application;

public sealed record LoginContext
{
    public string ClientApp { get; init; } = default!;
    public string ClientInfo { get; init; } = default!;
    public string OsInfo { get; init; } = default!;
    public string IpAddress { get; init; } = default!;
    public bool ForceLogin { get; init; }
    public Guid CorrelationId { get; init; }
}
