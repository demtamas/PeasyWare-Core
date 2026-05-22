namespace PeasyWare.Application.Dto;

/// <summary>
/// Inbound delivery header summary — used by the Desktop inbound list view.
/// </summary>
public sealed class InboundDeliverySummaryDto
{
    public int      InboundId         { get; init; }
    public string   InboundRef        { get; init; } = string.Empty;
    public string   StatusCode        { get; init; } = string.Empty;
    public string?  SupplierName      { get; init; }
    public string?  HaulierName       { get; init; }
    public string?  ExpectedArrival   { get; init; }
    public string?  InboundMode       { get; init; }
    public int      TotalLines        { get; init; }
    public int      TotalExpected     { get; init; }
    public int      TotalReceived     { get; init; }
    public int      TotalOutstanding  { get; init; }
    public int      TotalUnits        { get; init; }
}
