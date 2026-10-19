namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of applying or declining one finding of a bin count (counts.adjust).
///
/// Success means the finding was decided. For an apply, MovementId is the ledger
/// row that carried out the change - the same row the finding keeps, which is
/// what a future reversal works from. A refusal changes nothing and leaves the
/// finding undecided; ResultCode / FriendlyMessage say why (the record changed
/// since the count, the pallet is allocated, and so on).
///
/// UnresolvedFindings is how many findings of the count are still undecided.
/// </summary>
public sealed class CountApplyResult
{
    public bool    Success             { get; init; }
    public string  ResultCode          { get; init; } = string.Empty;
    public string  FriendlyMessage     { get; init; } = string.Empty;
    public int     FindingId           { get; init; }
    public string? FindingCode         { get; init; }
    public int     CountId             { get; init; }
    public int?    MovementId          { get; init; }
    public int     UnresolvedFindings  { get; init; }
}
