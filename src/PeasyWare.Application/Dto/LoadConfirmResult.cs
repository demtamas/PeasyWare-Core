namespace PeasyWare.Application.Dto;

public sealed class LoadConfirmResult
{
    public bool   Success         { get; init; }
    public string ResultCode      { get; init; } = string.Empty;
    public string FriendlyMessage { get; init; } = string.Empty;
}
