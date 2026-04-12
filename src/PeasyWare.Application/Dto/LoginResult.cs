
namespace PeasyWare.Application;

public sealed class LoginResult
{
    public bool Success { get; init; }
    public string ResultCode { get; init; } = null!;
    public string FriendlyMessage { get; init; } = null!;
    public int? UserId { get; init; }
    public Guid? SessionId { get; init; }
    public string? DisplayName { get; init; }
    public DateTime? LastLoginTime { get; init; }
    public int FailedAttempts { get; init; }
    public DateTime? LockoutUntil { get; init; }
    public int SessionTimeoutMinutes { get; set; }
}
