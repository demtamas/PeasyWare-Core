using System.ComponentModel.DataAnnotations;

namespace PeasyWare.API.Requests;

public sealed class CreateSkuRequest
{
    [Required, MaxLength(50)]
    public string SkuCode { get; init; } = null!;

    [Required, MaxLength(200)]
    public string SkuDescription { get; init; } = null!;

    [MaxLength(50)]
    public string? Ean { get; init; }

    [Required, MaxLength(20)]
    public string UomCode { get; init; } = "Each";

    public decimal? WeightPerUnit { get; init; }

    public int StandardHuQuantity { get; init; } = 0;

    public bool IsHazardous { get; init; } = false;
}
