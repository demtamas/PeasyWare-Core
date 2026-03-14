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
    // Authoritative login entry point (context REQUIRED)
    // --------------------------------------------------

    public LoginResult Login(
        string username,
        string? password,
        LoginContext context)
    {
        // 🚨 HARD GUARD — fail fast if client identity is missing
        if (string.IsNullOrWhiteSpace(context.ClientApp))
        {
            throw new InvalidOperationException(
                "LoginContext.ClientApp must be supplied by the client.");
        }

        // Audit: attempt (no UserId yet, no SessionId yet)
        _logger.Info(
            "Auth.LoginAttempt",
            new
            {
                Username = username,
                ClientApp = context.ClientApp,
                ClientInfo = context.ClientInfo,
                OsInfo = context.OsInfo,
                IpAddress = context.IpAddress,
                ForceLogin = context.ForceLogin,
                ResultCode = "ATTEMPT",
                Success = true
            });

        var result = _login.Login(username, password, context);

        if (!result.Success)
        {
            _logger.Warn(
                "Auth.LoginFailed",
                new
                {
                    Username = username,
                    ClientApp = context.ClientApp,
                    IpAddress = context.IpAddress,
                    ResultCode = result.ResultCode,
                    Success = false,
                    FailedAttempts = result.FailedAttempts,
                    LockoutUntil = result.LockoutUntil
                });

            return result;
        }

        _logger.Info(
            "Auth.LoginSuccess",
            new
            {
                UserId = result.UserId,
                SessionId = result.SessionId,
                Username = username,
                ClientApp = context.ClientApp,
                IpAddress = context.IpAddress,
                ResultCode = result.ResultCode,
                Success = true
            });

        return result;
    }

    // --------------------------------------------------
    // Password change (authoritative auth action)
    // --------------------------------------------------

    public OperationResult ChangePassword(
        string username,
        string newPassword)
    {
        _logger.Info(
            "Auth.PasswordChangeAttempt",
            new
            {
                Username = username,
                ResultCode = "ATTEMPT",
                Success = true
            });

        var result = _security.ChangePassword(username, newPassword);

        if (!result.Success)
        {
            _logger.Warn(
                "Auth.PasswordChangeFailed",
                new
                {
                    Username = username,
                    ResultCode = result.ResultCode,
                    Success = false
                });

            return result;
        }

        _logger.Info(
            "Auth.PasswordChangeSuccess",
            new
            {
                Username = username,
                ResultCode = result.ResultCode,
                Success = true
            });

        return result;
    }
}