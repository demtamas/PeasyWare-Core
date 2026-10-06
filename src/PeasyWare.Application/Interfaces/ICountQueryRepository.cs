using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ICountQueryRepository
{
    /// <summary>Storage types that have empty bins to count, or a count already open.</summary>
    IReadOnlyList<EmptyBinSummaryDto> GetEmptyBinSummary();

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

    /// <summary>Every pallet found during a count, oldest first.</summary>
    IReadOnlyList<CountFindingDto> GetFindings(int countId);
}
