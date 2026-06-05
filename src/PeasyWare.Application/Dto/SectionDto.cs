namespace PeasyWare.Application.Dto;

public sealed class SectionDto
{
    public int      SectionId          { get; init; }
    public string   SectionCode        { get; init; } = null!;
    public string   SectionName        { get; init; } = null!;
    public string?  Description        { get; init; }
    public bool     IsActive           { get; init; }
    public DateTime CreatedAt          { get; init; }
    public string?  CreatedByUsername  { get; init; }
    public DateTime? UpdatedAt         { get; init; }
    public string?  UpdatedByUsername  { get; init; }
    public int      TotalBins          { get; init; }
    public int      ActiveBins         { get; init; }
}
