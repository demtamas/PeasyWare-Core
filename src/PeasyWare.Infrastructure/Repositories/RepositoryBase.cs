using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;

namespace PeasyWare.Infrastructure.Repositories;

public abstract class RepositoryBase
{
    private readonly SessionGuard          _sessionGuard;
    private readonly Guid                  _sessionId;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;
    private readonly SessionContext        _session;

    protected RepositoryBase(
        SessionGuard          sessionGuard,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger)
    {
        _sessionGuard = sessionGuard;
        _sessionId    = session.SessionId;
        _session      = session;
        _resolver     = resolver;
        _logger       = logger;
    }

    protected void EnsureSession()
    {
        _sessionGuard.EnsureActive(_sessionId);
    }

    /// <summary>
    /// Resolves the friendly message, logs at the appropriate level,
    /// and returns a structured OperationResult.
    /// Use only for methods that return OperationResult directly.
    /// Rich-DTO methods (PutawayTaskResult, PickTaskResult etc.) handle
    /// their own logging since they need action-specific payloads.
    /// </summary>
    protected OperationResult BuildResult(
        string action,
        string resultCode,
        object data)
    {
        var success = resultCode.StartsWith("SUC", StringComparison.OrdinalIgnoreCase);
        var message = _resolver.Resolve(resultCode);
        var result  = OperationResult.Create(success, resultCode, message);

        var payload = new
        {
            _session.UserId,
            _session.SessionId,
            _session.CorrelationId,
            ResultCode = resultCode,
            Success    = success,
            Data       = data
        };

        if (success)
            _logger.Info(action, payload);
        else
            _logger.Warn(action, payload);

        return result;
    }
}