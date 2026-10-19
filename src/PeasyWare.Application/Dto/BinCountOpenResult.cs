namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of opening a bin for counting (the operator scanned its label).
/// Success means the bin is now held for the count. Resumed is true when the
/// bin was already open - PalletsScanned is then what was recorded so far.
/// Says nothing about what the system holds in the bin: the count is blind.
/// </summary>
public sealed class BinCountOpenResult
{
    public bool    Success         { get; init; }
    public string  ResultCode      { get; init; } = string.Empty;
    public string  FriendlyMessage { get; init; } = string.Empty;
    public int     CountId         { get; init; }
    public string  BinCode         { get; init; } = string.Empty;
    public int     PalletsScanned  { get; init; }
    public int     PendingBins     { get; init; }
    public bool    Resumed         { get; init; }
}
