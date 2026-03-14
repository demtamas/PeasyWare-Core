namespace PeasyWare.Application;

public sealed class LoginContext
{
    public string? ClientInfo { get; init; }
    public string? IpAddress { get; init; }
    public string? ClientApp { get; init; }
    public string? OsInfo { get; init; }
    public bool ForceLogin { get; init; }
}
