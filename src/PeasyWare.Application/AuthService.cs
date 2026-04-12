using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application;

public sealed class AuthService
{
    private readonly ILoginRepository _login;
    private readonly IUserSecurityRepository _security;
    private readonly ILogger _logger;

    public AuthService(
        ILoginRepository login,
        IUserSecurityRepository security,
        ILogger logger)
    {
        _login = login;
        _security = security;
        _logger = logger;
    }

    // --------------------------------------------------
    // Authoritative login entry point
    // --------------------------------------------------

    public LoginResult Login(
        string username,
        string? password,
        LoginContext context)
    {
        // 🚨 HARD GUARD
        if (string.IsNullOrWhiteSpace(context.ClientApp))
        {
            throw new InvalidOperationException(
                "LoginContext.ClientApp must be supplied by the client.");
        }

        // 🔍 TRACE (not domain event)
        _logger.Info("AuthService.Login.Start", new
        {
            Username = username,
            context.ClientApp,
            context.ClientInfo,
            context.IpAddress,
            context.CorrelationId
        });

        var result = _login.Login(username, password, context);

        // 🔍 TRACE outcome (not domain event)
        _logger.Info("AuthService.Login.Result", new
        {
            Username = username,
            result.ResultCode,
            result.Success,
            result.FailedAttempts,
            result.LockoutUntil,
            context.CorrelationId
        });

        return result;
    }

    // --------------------------------------------------
    // Password change
    // --------------------------------------------------

    public OperationResult ChangePassword(
        string username,
        string newPassword)
    {
        _logger.Info("AuthService.PasswordChange.Start", new
        {
            Username = username
        });

        var result = _security.ChangePassword(username, newPassword);

        _logger.Info("AuthService.PasswordChange.Result", new
        {
            Username = username,
            result.ResultCode,
            result.Success
        });

        return result;
    }
}