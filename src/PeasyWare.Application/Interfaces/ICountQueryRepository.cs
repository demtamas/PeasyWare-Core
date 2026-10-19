using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ICountQueryRepository
{
    /// <summary>Storage types that have empty bins to count, or a count already open.</summary>
    IReadOnlyList<EmptyBinSummaryDto> GetEmptyBinSummary();

    /// <summary>
    /// Storage types that have bins holding stock to bin-count, or a bin count already
    /// open. Says nothing about what is in the bins: the count is blind.
    /// </summary>
    IReadOnlyList<BinCountSummaryDto> GetBinCountSummary();

    /// <summary>
    /// True if the code, matched exactly, is an active bin in an active storage type -
    /// i.e. one that can be named in an ad hoc count (empty or occupied).
    /// </summary>
    bool IsCountableBin(string binCode);

    /// <summary>Bins in the count not yet visited, in walk order (zone, then bin).</summary>
    IReadOnlyList<CountLineDto> GetPendingLines(int countId);

    /// <summary>A count and its progress; null if it does not exist.</summary>
    CountSessionDto? GetSession(int countId);

    /// <summary>
    /// Counts with their progress, newest first. needsAttentionOnly limits it to the
    /// ones that still need someone: OPEN (in progress) and REVIEW (found something
    /// to deal with). Otherwise the most recent 200.
    /// </summary>
    IReadOnlyList<CountSessionDto> GetSessions(bool needsAttentionOnly);

    /// <summary>Every bin in a count, whatever its status, in walk order.</summary>
    IReadOnlyList<CountLineDto> GetLines(int countId);

    /// <summary>Everything a count found, oldest first.</summary>
    IReadOnlyList<CountFindingDto> GetFindings(int countId);
}
