namespace PeasyWare.Application.Dto;

/// <summary>
/// One bin within a count. PalletsScanned is what the operator has scanned in it
/// so far (bin counts; 0 for an empty-bin check). Says nothing about what the
/// system holds in the bin.
/// </summary>
public sealed class CountLineDto
{
    public int        CountLineId      { get; init; }
    public int        CountId          { get; init; }
    public string     BinCode          { get; init; } = string.Empty;
    public string?    ZoneCode         { get; init; }
    public string?    StorageTypeCode  { get; init; }
    public string     LineStatusCode   { get; init; } = string.Empty;
    public DateTime?  OpenedAt         { get; init; }
    public DateTime?  CountedAt        { get; init; }
    public string?    CountedBy        { get; init; }
    public int        PalletsScanned   { get; init; }
    public int        FindingCount     { get; init; }
}
