namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of confirming a bin empty. Success means the line was recorded;
/// IsWarning distinguishes "recorded, but look at this" (WARN codes) from a clean outcome.
/// </summary>
public sealed class CountBinResult
{
    public bool    Success         { get; init; }
    public string  ResultCode      { get; init; } = string.Empty;
    public string  FriendlyMessage { get; init; } = string.Empty;
    public int     CountId         { get; init; }
    public int     PendingBins     { get; init; }

    public bool IsWarning =>
        ResultCode.StartsWith("WARN", StringComparison.OrdinalIgnoreCase);
}
