namespace PeasyWare.Application.Dto;

/// <summary>
/// One row per storage type for the "which storage type to count" picker:
/// how many bins are empty right now, and whether a count is already open
/// for it (and how many bins that count still has to check).
/// </summary>
public sealed class EmptyBinSummaryDto
{
    public string  StorageTypeCode    { get; init; } = string.Empty;
    public string  StorageTypeName    { get; init; } = string.Empty;
    public int     EmptyBins          { get; init; }
    public int?    OpenCountId        { get; init; }
    public int?    OpenPendingBins    { get; init; }
}
