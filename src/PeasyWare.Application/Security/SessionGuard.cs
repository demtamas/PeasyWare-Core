using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application.Security;

public sealed class SessionGuard
{
    private readonly ISessionCommandRepository _sessionRepo;

    public SessionGuard(ISessionCommandRepository sessionRepo)
    {
        _sessionRepo = sessionRepo;
    }

    public void EnsureActive(Guid sessionId)
    {
        var result = _sessionRepo.TouchSession(
            sessionId,
            "PeasyWare.Desktop",
            Environment.MachineName,
            null);

        if (!result.IsAlive)
        {
            throw new SessionExpiredException(
                result.FriendlyMessage ?? "Your session has expired.");
        }
    }
}