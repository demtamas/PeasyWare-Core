namespace PeasyWare.Application.Dto;

/// <summary>
/// A count and its progress (warehouse.v_count_sessions).
///
/// StatusCode: OPEN (in progress), REVIEW (finished, but it found something a
/// person has to deal with), COMPLETE / CLOSED (finished, nothing outstanding).
/// FindingsToReview is how many pallets the count found but could not put right;
/// ReviewedAt / ReviewedBy / ReviewNote record who dealt with it and what they did.
/// </summary>
public sealed class CountSessionDto
{
    public int        CountId          { get; init; }
    public string     CountTypeCode    { get; init; } = string.Empty;
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
    public int        FindingsToReview { get; init; }
    public DateTime?  ReviewedAt       { get; init; }
    public string?    ReviewedBy       { get; init; }
    public string?    ReviewNote       { get; init; }

    /// <summary>True while the count is waiting for a person to deal with its findings.</summary>
    public bool AwaitsReview => StatusCode == "REVIEW";
}
