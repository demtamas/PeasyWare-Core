namespace PeasyWare.Application;

public sealed class OperationResult
{
    public bool Success { get; }
    public string ResultCode { get; }
    public string FriendlyMessage { get; }

    private OperationResult(bool success, string code, string message)
    {
        Success = success;
        ResultCode = code;
        FriendlyMessage = message;
    }

    public static OperationResult Create(
        bool success,
        string code,
        string message)
        => new(success, code, message);
}