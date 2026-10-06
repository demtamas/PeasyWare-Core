namespace PeasyWare.Application.Dto;

/// <summary>One bin within a count.</summary>
public sealed class CountLineDto
{
    public int        CountLineId      { get; init; }
    public int        CountId          { get; init; }
    public string     BinCode          { get; init; } = string.Empty;
    public string?    ZoneCode         { get; init; }
    public string?    StorageTypeCode  { get; init; }
    public string     LineStatusCode   { get; init; } = string.Empty;
    public DateTime?  CountedAt        { get; init; }
    public string?    CountedBy        { get; init; }
    public int        FindingCount     { get; init; }
}
