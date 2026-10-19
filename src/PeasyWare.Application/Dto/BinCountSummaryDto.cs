namespace PeasyWare.Application.Dto;

/// <summary>
/// One storage type in the bin-count picker: how many of its bins hold stock
/// (warehouse.v_occupied_bins), and the bin count already open for it, if any,
/// so the operator can resume it. Says nothing about what is IN the bins - the
/// count is blind.
/// </summary>
public sealed class BinCountSummaryDto
{
    public string StorageTypeCode { get; init; } = string.Empty;
    public string StorageTypeName { get; init; } = string.Empty;
    public int    BinsWithStock   { get; init; }
    public int?   OpenCountId     { get; init; }
    public int?   OpenPendingBins { get; init; }
}
