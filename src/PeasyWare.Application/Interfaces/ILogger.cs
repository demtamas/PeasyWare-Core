using PeasyWare.Application.Contexts;

namespace PeasyWare.Application.Interfaces;

public interface ILogger
{
    void SetSession(SessionContext session);

    /// <summary>
    /// Forgets the current session, so later entries are written as pre-session (no user,
    /// no session) instead of inheriting whoever was logged in last. Called when a user
    /// logs out and the next login screen is about to appear: without it, a failed login
    /// attempt by anyone would be recorded under the previous user's identity.
    ///
    /// A default (no-op) implementation keeps every existing implementer compiling;
    /// the real logger overrides it.
    /// </summary>
    void ClearSession() { }

    void Info(string action, object? data);
    void Warn(string action, object? data);
    void Error(string action, object? data);
    void Error(string action, object? data, Exception ex);
}
