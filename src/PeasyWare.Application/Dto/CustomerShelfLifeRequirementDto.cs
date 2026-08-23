namespace PeasyWare.Application.Dto;

public sealed class CustomerShelfLifeRequirementDto
{
    public int      CustomerPartyId               { get; init; }
    public string    CustomerPartyCode             { get; init; } = string.Empty;
    public string    CustomerName                  { get; init; } = string.Empty;
    public int      SkuId                          { get; init; }
    public string    SkuCode                        { get; init; } = string.Empty;
    public string    SkuDescription                 { get; init; } = string.Empty;
    public int      MinimumRemainingShelfLifeDays  { get; init; }
    public DateTime  CreatedAt                      { get; init; }
    public string?   CreatedByUsername              { get; init; }
    public DateTime? UpdatedAt                      { get; init; }
    public string?   UpdatedByUsername              { get; init; }
}
