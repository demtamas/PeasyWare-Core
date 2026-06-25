namespace PeasyWare.Application.Dto;

public sealed class StorageTypeDto
{
    public int       StorageTypeId     { get; init; }
    public string    StorageTypeCode   { get; init; } = null!;
    public string    StorageTypeName   { get; init; } = null!;
    public string?   Description       { get; init; }
    public bool      IsActive          { get; init; }
    public DateTime  CreatedAt         { get; init; }
    public string?   CreatedByUsername { get; init; }
    public DateTime? UpdatedAt         { get; init; }
    public string?   UpdatedByUsername { get; init; }
    public int       TotalBins         { get; init; }
    public int       ActiveBins        { get; init; }
}
