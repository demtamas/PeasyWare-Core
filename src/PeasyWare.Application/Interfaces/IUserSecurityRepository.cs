using PeasyWare.Application;

namespace PeasyWare.Application.Interfaces;

public interface IUserSecurityRepository
{
    /// <summary>
    /// Changes a password. <paramref name="correlationId"/> is the correlation ID of the
    /// login attempt that demanded the change (ERRAUTH09), so the change is logged on the
    /// same trace as that attempt instead of floating free of it. Guid.Empty = none.
    /// </summary>
    OperationResult ChangePassword(
        string username,
        string newPassword,
        Guid   correlationId = default);
}
