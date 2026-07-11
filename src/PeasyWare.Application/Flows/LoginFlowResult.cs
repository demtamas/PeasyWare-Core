namespace PeasyWare.Application.Flows;

public sealed class LoginFlowResult
{
    public bool Success { get; }
    public Guid? SessionId { get; }
    public int? UserId { get; }
    public string? DisplayName { get; }
    public string? RoleName { get; }
    public UiMode UiMode { get; }
    public LoginOutcome Outcome { get; }
    public string? Message { get; }
    public int SessionTimeoutMinutes { get; set; }
    public IReadOnlySet<string> Permissions { get; }

    private LoginFlowResult(
        bool success,
        Guid? sessionId,
        int? userId,
        string? displayName,
        string? roleName,
        UiMode uiMode,
        LoginOutcome outcome,
        string? message,
        int sessionTimeoutMinutes,
        IReadOnlySet<string>? permissions = null)
    {
        Success = success;
        SessionId = sessionId;
        UserId = userId;
        DisplayName = displayName;
        RoleName = roleName;
        UiMode = uiMode;
        Outcome = outcome;
        Message = message;
        SessionTimeoutMinutes = sessionTimeoutMinutes;
        Permissions = permissions ?? new HashSet<string>();
    }

    public static LoginFlowResult Succeeded(
        Guid sessionId,
        int userId,
        string? displayName,
        string? roleName,
        UiMode uiMode,
        int sessionTimeoutMinutes,
        IReadOnlySet<string>? permissions = null)
        => new(true, sessionId, userId, displayName, roleName, uiMode,
               LoginOutcome.Success, null, sessionTimeoutMinutes, permissions);

    public static LoginFlowResult Failed(string? message = null)
        => new(false, null, null, null, null, UiMode.Minimal,
               LoginOutcome.Failed, message, 0);

    public static LoginFlowResult PasswordChangeRequired(string? message)
        => new(false, null, null, null, null, UiMode.Minimal,
               LoginOutcome.PasswordChangeRequired, message, 0);

    public static LoginFlowResult AlreadyLoggedIn(string? message)
        => new(false, null, null, null, null, UiMode.Minimal,
               LoginOutcome.AlreadyLoggedIn, message, 0);

    public static LoginFlowResult Cancelled()
        => new(false, null, null, null, null, UiMode.Minimal,
               LoginOutcome.Cancelled, null, 0);
}
