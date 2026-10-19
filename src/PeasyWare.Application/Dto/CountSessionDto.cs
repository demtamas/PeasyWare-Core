namespace PeasyWare.Application.Dto;

/// <summary>
/// A count and its progress (warehouse.v_count_sessions).
///
/// CountTypeCode: EMPTY_BIN (bins the system believes are empty) or BIN_COUNT (a
/// blind count of bins).
///
/// ScopeCode says what a count covers: STORAGE_TYPE (one storage type, named in
/// StorageTypeCode), ALL (a bin-count sweep over every storage type) or ADHOC (a
/// hand-picked list of bins). Sweep and ad hoc counts have no StorageTypeCode.
///
/// StatusCode: OPEN (in progress), REVIEW (finished, but it found something a
/// person has to deal with), COMPLETE / CLOSED (finished, nothing outstanding).
/// FindingsToReview is how many findings are still undecided (everything except a
/// record the count itself corrected, and anything already applied or declined);
/// ReviewedAt / ReviewedBy / ReviewNote record who dealt with it and what they did.
///
/// Bin outcomes - EMPTY_BIN: ConfirmedEmpty / StockFound / OccupiedSince.
/// BIN_COUNT: CountingBins (open right now), MatchedBins, DifferenceBins.
/// </summary>
public sealed class CountSessionDto
{
    public int        CountId          { get; init; }
    public string     CountTypeCode    { get; init; } = string.Empty;
    public string     ScopeCode        { get; init; } = "STORAGE_TYPE";
    public string?    StorageTypeCode  { get; init; }
    public string     StatusCode       { get; init; } = string.Empty;
    public DateTime   StartedAt        { get; init; }
    public string?    StartedBy        { get; init; }
    public DateTime?  CompletedAt      { get; init; }
    public string?    CompletedBy      { get; init; }
    public int        TotalBins        { get; init; }
    public int        PendingBins      { get; init; }
    public int        ConfirmedEmpty   { get; init; }
    public int        StockFound       { get; init; }
    public int        OccupiedSince    { get; init; }
    public int        CountingBins     { get; init; }
    public int        MatchedBins      { get; init; }
    public int        DifferenceBins   { get; init; }
    public int        FindingsToReview { get; init; }
    public DateTime?  ReviewedAt       { get; init; }
    public string?    ReviewedBy       { get; init; }
    public string?    ReviewNote       { get; init; }

    /// <summary>True while the count is waiting for a person to deal with its findings.</summary>
    public bool AwaitsReview => StatusCode == "REVIEW";

    /// <summary>A bin count over every storage type.</summary>
    public bool IsSweep => ScopeCode == "ALL";

    /// <summary>A bin count of a hand-picked list of bins.</summary>
    public bool IsAdHoc => ScopeCode == "ADHOC";

    /// <summary>
    /// What the count covers, for display: the storage type, "All storage types" for
    /// a sweep, or "Ad hoc" for a hand-picked list of bins.
    /// </summary>
    public string ScopeText => ScopeCode switch
    {
        "ALL"   => "All storage types",
        "ADHOC" => "Ad hoc (selected bins)",
        _       => StorageTypeCode ?? string.Empty
    };
}
