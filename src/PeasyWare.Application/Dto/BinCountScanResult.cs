namespace PeasyWare.Application.Dto;

/// <summary>
/// Result of scanning one pallet (SSCC + counted quantity) in an open bin.
///
/// The count is blind, so this never carries what the system holds. The one
/// exception to "the result is just recorded" is NeedsConfirmation: the pallet is
/// recorded in this bin and the quantity entered differs from the system's, so
/// NOTHING was recorded yet - the caller asks the operator to confirm the
/// quantity (or enter it again) and calls again with confirmDifference = true.
///
/// HoldExpired: the bin's hold ran out (the operator was away). Opening the bin
/// again resumes it with the scans so far kept; the scan can then be repeated.
/// </summary>
public sealed class BinCountScanResult
{
    public bool    Success            { get; init; }
    public string  ResultCode         { get; init; } = string.Empty;
    public string  FriendlyMessage    { get; init; } = string.Empty;
    public int     CountId            { get; init; }
    public int     PalletsScanned     { get; init; }
    public bool    Replaced           { get; init; }
    public bool    NeedsConfirmation  { get; init; }

    public bool HoldExpired =>
        string.Equals(ResultCode, "ERRCNT16", StringComparison.OrdinalIgnoreCase);
}
