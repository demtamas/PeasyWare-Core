namespace PeasyWare.Application.Interfaces;

public sealed class LogoutResult
{
    public bool Success { get; }
    public string? ResultCode { get; }
    public string? FriendlyMessage { get; }

    public LogoutResult(bool success, string? resultCode, string? friendlyMessage)
    {
        Success = success;
        ResultCode = resultCode;
        FriendlyMessage = friendlyMessage;
    }
}
