namespace PeasyWare.Application.Flows;

public enum LoginOutcome
{
    Success,
    Failed,
    PasswordChangeRequired,
    AlreadyLoggedIn,
    Cancelled
}
