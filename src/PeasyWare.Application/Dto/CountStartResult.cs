namespace PeasyWare.Application.Dto;

/// <summary>Result of starting (or resuming) an empty-bin count.</summary>
public sealed class CountStartResult
{
    public bool    Success         { get; init; }
    public string  ResultCode      { get; init; } = string.Empty;
    public string  FriendlyMessage { get; init; } = string.Empty;
    public int     CountId         { get; init; }
    public int     TotalBins       { get; init; }
    public int     PendingBins     { get; init; }
    public bool    Resumed         { get; init; }
}
