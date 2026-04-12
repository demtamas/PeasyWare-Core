using PeasyWare.Application.Security;

namespace PeasyWare.Infrastructure.Repositories;

public abstract class RepositoryBase
{
    private readonly SessionGuard _sessionGuard;
    private readonly Guid _sessionId;

    protected RepositoryBase(
        SessionGuard sessionGuard,
        Guid sessionId)
    {
        _sessionGuard = sessionGuard;
        _sessionId = sessionId;
    }

    protected void EnsureSession()
    {
        _sessionGuard.EnsureActive(_sessionId);
    }
}