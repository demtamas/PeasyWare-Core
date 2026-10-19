namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of starting (or resuming) a count.
///
/// InvalidBinCode is set only when an ad hoc count was refused because one of the
/// bins chosen is not an active bin: it is the first such code, exactly as entered.
/// </summary>
public sealed class CountStartResult
{
    public bool    Success         { get; init; }
    public string  ResultCode      { get; init; } = string.Empty;
    public string  FriendlyMessage { get; init; } = string.Empty;
    public int     CountId         { get; init; }
    public int     TotalBins       { get; init; }
    public int     PendingBins     { get; init; }
    public bool    Resumed         { get; init; }
    public string? InvalidBinCode  { get; init; }
}
