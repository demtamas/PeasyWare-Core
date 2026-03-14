using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application.Flows;

public sealed class LoginFlow
{
    private readonly AuthService _authService;

    public LoginFlow(AuthService authService, IUserSecurityRepository userSecurityRepository)
    {
        _authService = authService;
    }

    public LoginFlowResult Run(
        string username,
        string password,
        LoginContext context,
        bool diagnosticsEnabled)
    {
        var loginResult = _authService.Login(
            username,
            password,
            context);

        return loginResult.ResultCode switch
        {
            "SUCAUTH01" => LoginFlowResult.Succeeded(
                loginResult.SessionId!.Value,
                loginResult.UserId!.Value),

            "ERRAUTH09" => LoginFlowResult.PasswordChangeRequired(
                loginResult.FriendlyMessage),

            "ERRAUTH05" => LoginFlowResult.AlreadyLoggedIn(
                loginResult.FriendlyMessage),

            _ => LoginFlowResult.Failed(
                loginResult.FriendlyMessage)
        };
    }

    public OperationResult ChangePassword(
        string username,
        string newPassword)
        => _authService.ChangePassword(username, newPassword);
}