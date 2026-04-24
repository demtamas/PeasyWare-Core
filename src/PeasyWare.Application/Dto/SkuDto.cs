namespace PeasyWare.Application.Dto;

public sealed class SkuDto
{
    public int      SkuId              { get; init; }
    public string   SkuCode            { get; init; } = null!;
    public string   SkuDescription     { get; init; } = null!;
    public string?  Ean                { get; init; }
    public string   UomCode            { get; init; } = null!;
    public decimal? WeightPerUnit      { get; init; }
    public int      StandardHuQuantity { get; init; }
    public bool     IsHazardous        { get; init; }
    public bool     IsActive           { get; init; }
}
