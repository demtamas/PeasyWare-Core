namespace PeasyWare.Application;

public sealed class SessionTouchResult
{
    /// <summary>
    /// True if the session is valid and refreshed.
    /// False if the session is missing, inactive, or expired.
    /// </summary>
    public bool IsAlive { get; init; }

    /// <summary>
    /// Result code returned by the database (e.g. SUCAUTH02, ERRAUTH06).
    /// </summary>
    public string ResultCode { get; init; } = null!;

    /// <summary>
    /// User-facing friendly message resolved by the database.
    /// </summary>
    public string FriendlyMessage { get; init; } = null!;
}
