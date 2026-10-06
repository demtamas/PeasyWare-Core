namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of closing a count. FinalStatus is REVIEW (it found something a person
/// has to deal with - see FindingsToReview), COMPLETE (every bin visited) or
/// CLOSED (closed with bins still uncounted).
/// </summary>
public sealed class CountCloseResult
{
    public bool     Success          { get; init; }
    public string   ResultCode       { get; init; } = string.Empty;
    public string   FriendlyMessage  { get; init; } = string.Empty;
    public int      CountId          { get; init; }
    public int      PendingBins      { get; init; }
    public string?  FinalStatus      { get; init; }
    public int      FindingsToReview { get; init; }
}
