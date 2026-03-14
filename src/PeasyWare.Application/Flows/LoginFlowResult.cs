namespace PeasyWare.Application.Flows;

public sealed class LoginFlowResult
{
    public bool Success { get; }
    public Guid? SessionId { get; }
    public int? UserId { get; }
    public LoginOutcome Outcome { get; }
    public string? Message { get; }

    private LoginFlowResult(
        bool success,
        Guid? sessionId,
        int? userId,
        LoginOutcome outcome,
        string? message)
    {
        Success = success;
        SessionId = sessionId;
        UserId = userId;
        Outcome = outcome;
        Message = message;
    }

    public static LoginFlowResult Succeeded(Guid sessionId, int userId)
        => new(true, sessionId, userId, LoginOutcome.Success, null);

    public static LoginFlowResult Failed(string? message = null)
        => new(false, null, null, LoginOutcome.Failed, message);

    public static LoginFlowResult PasswordChangeRequired(string? message)
        => new(false, null, null, LoginOutcome.PasswordChangeRequired, message);

    public static LoginFlowResult AlreadyLoggedIn(string? message)
        => new(false, null, null, LoginOutcome.AlreadyLoggedIn, message);

    public static LoginFlowResult Cancelled()
        => new(false, null, null, LoginOutcome.Cancelled, null);
}
