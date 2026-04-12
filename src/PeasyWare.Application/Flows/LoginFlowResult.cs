namespace PeasyWare.Application.Flows;

public sealed class LoginFlowResult
{
    public bool Success { get; }
    public Guid? SessionId { get; }
    public int? UserId { get; }
    public string? DisplayName { get; }
    public LoginOutcome Outcome { get; }
    public string? Message { get; }
    public int SessionTimeoutMinutes { get; set; }

    private LoginFlowResult(
    bool success,
    Guid? sessionId,
    int? userId,
    string? displayName,
    LoginOutcome outcome,
    string? message,
    int sessionTimeoutMinutes)   // 👈 ADD
    {
        Success = success;
        SessionId = sessionId;
        UserId = userId;
        DisplayName = displayName;
        Outcome = outcome;
        Message = message;
        SessionTimeoutMinutes = sessionTimeoutMinutes; // 👈 ADD
    }

    public static LoginFlowResult Succeeded(
    Guid sessionId,
    int userId,
    string? displayName,
    int sessionTimeoutMinutes)
    => new(true, sessionId, userId, displayName, LoginOutcome.Success, null, sessionTimeoutMinutes);

    public static LoginFlowResult Failed(string? message = null)
    => new(false, null, null, null, LoginOutcome.Failed, message, 0);

    public static LoginFlowResult PasswordChangeRequired(string? message)
        => new(false, null, null, null, LoginOutcome.PasswordChangeRequired, message, 0);

    public static LoginFlowResult AlreadyLoggedIn(string? message)
        => new(false, null, null, null, LoginOutcome.AlreadyLoggedIn, message, 0);

    public static LoginFlowResult Cancelled()
        => new(false, null, null, null, LoginOutcome.Cancelled, null, 0);
}
