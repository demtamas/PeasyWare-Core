namespace PeasyWare.Application.Dto;

public sealed class PartyDto
{
    public int      PartyId             { get; init; }
    public string   PartyCode           { get; init; } = string.Empty;
    public string   LegalName           { get; init; } = string.Empty;
    public string   DisplayName         { get; init; } = string.Empty;
    public string?  CountryCode         { get; init; }
    public string?  TaxId               { get; init; }
    public bool     IsActive            { get; init; }
    public string   Roles               { get; init; } = string.Empty;  // comma-separated display
    public bool     IsSupplier          { get; init; }
    public bool     IsCustomer          { get; init; }
    public bool     IsHaulier           { get; init; }
    public bool     IsOwner             { get; init; }
    public bool     IsWarehouse         { get; init; }
    public DateTime? CreatedAt          { get; init; }
    public string?  CreatedByUsername   { get; init; }
    public DateTime? UpdatedAt          { get; init; }
    public string?  UpdatedByUsername   { get; init; }
}
