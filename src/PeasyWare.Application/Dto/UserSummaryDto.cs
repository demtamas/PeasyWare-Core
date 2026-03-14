namespace PeasyWare.Application.Dto;

public sealed class UserSummaryDto
{
    public int UserId { get; init; }
    public string Username { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public string? Email { get; init; }
    public string RoleName { get; init; } = "";
    public bool IsActive { get; init; }

    // From view
    public bool IsOnline { get; init; }
    public DateTime? LastLastSeen { get; init; }
    public bool MustChangePassword { get; init; }
    public int FailedAttempts { get; init; }
    public DateTime? LockoutUntil { get; init; }
    public bool IsLockedOut =>
        LockoutUntil.HasValue && LockoutUntil.Value > DateTime.UtcNow;
    public DateTime? PasswordExpiresAt { get; init; }
    public DateTime CreatedAt { get; init; }
    public int? CreatedByUserId { get; init; }
    public DateTime? UpdatedAt { get; init; }
    public int? UpdatedByUserId { get; init; }
}
