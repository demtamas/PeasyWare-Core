namespace PeasyWare.Application.Dto;

public sealed record SkuDto
{
    public int      SkuId                     { get; init; }
    public string   SkuCode                   { get; init; } = null!;
    public string   SkuDescription            { get; init; } = null!;
    public string?  Ean                       { get; init; }
    public string   UomCode                   { get; init; } = null!;
    public decimal? WeightPerUnit             { get; init; }
    public int      StandardHuQuantity        { get; init; }
    public bool     IsHazardous               { get; init; }
    public bool     IsBatchRequired           { get; init; }
    public bool     IsFullHuRequired          { get; init; }
    public bool     IsActive                  { get; init; }
    public string?  PreferredStorageTypeCode  { get; init; }
    public string?  PreferredSectionCode      { get; init; }
    public string?  OwnerPartyCode            { get; init; }
    public string?  OwnerName                 { get; init; }
    public DateTime? CreatedAt               { get; init; }
    public string?  CreatedByUsername         { get; init; }
    public DateTime? UpdatedAt               { get; init; }
    public string?  UpdatedByUsername         { get; init; }
}
