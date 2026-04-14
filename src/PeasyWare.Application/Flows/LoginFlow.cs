using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application.Flows;

public sealed class LoginFlow
{
    private readonly AuthService _authService;
    private readonly UiMode _defaultUiMode;

    public LoginFlow(
        AuthService authService,
        IUserSecurityRepository userSecurityRepository,
        UiMode defaultUiMode)
    {
        _authService = authService;
        _defaultUiMode = defaultUiMode;
    }

    public LoginFlowResult Run(
        string username,
        string password,
        LoginContext context,
        bool diagnosticsEnabled)
    {
        var ctx = context.CorrelationId == Guid.Empty
            ? context with { CorrelationId = Guid.NewGuid() }
            : context;

        var loginResult = _authService.Login(username, password, ctx);

        return loginResult.ResultCode switch
        {
            "SUCAUTH01" => LoginFlowResult.Succeeded(
                loginResult.SessionId!.Value,
                loginResult.UserId!.Value,
                loginResult.DisplayName,
                loginResult.RoleName,
                ResolveUiMode(loginResult.RoleName),
                loginResult.SessionTimeoutMinutes),

            "ERRAUTH09" => LoginFlowResult.PasswordChangeRequired(
                loginResult.FriendlyMessage),

            "ERRAUTH05" => LoginFlowResult.AlreadyLoggedIn(
                loginResult.FriendlyMessage),

            _ => LoginFlowResult.Failed(loginResult.FriendlyMessage)
        };
    }

    public OperationResult ChangePassword(
        string username,
        string newPassword)
        => _authService.ChangePassword(username, newPassword);

    // --------------------------------------------------
    // Resolve UiMode from role, capped by system default
    //
    // The system default acts as a global ceiling.
    // No role can exceed it.
    //
    // Examples:
    //   Default = Minimal  → everyone sees Minimal
    //   Default = Standard → admin=Standard, manager=Standard, operator=Minimal
    //   Default = Trace    → admin=Trace, manager=Standard, operator=Minimal
    // --------------------------------------------------

    private UiMode ResolveUiMode(string? roleName)
    {
        var roleMax = roleName?.ToLowerInvariant() switch
        {
            "admin"   => UiMode.Trace,
            "manager" => UiMode.Standard,
            _         => UiMode.Minimal
        };

        return (UiMode)Math.Min((int)roleMax, (int)_defaultUiMode);
    }
}
