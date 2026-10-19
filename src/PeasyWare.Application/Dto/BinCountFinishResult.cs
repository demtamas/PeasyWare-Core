namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of finishing a bin: what was scanned has been compared with the
/// system and every difference recorded as a finding (no stock record changed).
///
/// Differences is how many findings were recorded - not what they are; the
/// operator is not told, only that there is something for a supervisor.
///
/// RecountRequired: the movement ledger showed the bin changed while it was being
/// counted, so nothing was recorded and the bin is back to be counted again.
/// </summary>
public sealed class BinCountFinishResult
{
    public bool    Success          { get; init; }
    public string  ResultCode       { get; init; } = string.Empty;
    public string  FriendlyMessage  { get; init; } = string.Empty;
    public int     CountId          { get; init; }
    public int     PalletsScanned   { get; init; }
    public int     Differences      { get; init; }
    public int     PendingBins      { get; init; }
    public bool    RecountRequired  { get; init; }

    public bool HasDifferences => Differences > 0;
}
