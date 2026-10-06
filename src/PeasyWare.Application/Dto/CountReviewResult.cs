namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of marking a count reviewed. FinalStatus is COMPLETE (every bin was
/// visited) or CLOSED (bins were left uncounted).
/// </summary>
public sealed class CountReviewResult
{
    public bool     Success         { get; init; }
    public string   ResultCode      { get; init; } = string.Empty;
    public string   FriendlyMessage { get; init; } = string.Empty;
    public int      CountId         { get; init; }
    public string?  FinalStatus     { get; init; }
}
