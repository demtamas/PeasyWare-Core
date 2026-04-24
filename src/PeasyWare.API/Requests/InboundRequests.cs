using System.ComponentModel.DataAnnotations;

namespace PeasyWare.API.Requests;

public sealed class CreateInboundRequest
{
    [Required, MaxLength(50)]
    public string InboundRef { get; init; } = null!;

    [Required]
    public string SupplierPartyCode { get; init; } = null!;

    public string? HaulierPartyCode { get; init; }

    public DateTime? ExpectedArrivalAt { get; init; }
}

public sealed class AddInboundLineRequest
{
    [Required, MaxLength(50)]
    public string SkuCode { get; init; } = null!;

    [Range(1, int.MaxValue)]
    public int ExpectedQty { get; init; }

    [MaxLength(100)]
    public string? BatchNumber { get; init; }

    public DateOnly? BestBeforeDate { get; init; }

    public string ArrivalStockStatus { get; init; } = "AV";
}

public sealed class AddExpectedUnitsRequest
{
    [Required, MinLength(1)]
    public List<ExpectedUnitItem> Units { get; init; } = new();
}

public sealed class ExpectedUnitItem
{
    /// <summary>
    /// 18-digit SSCC without AI prefix. Leading zeros included.
    /// Accepts scanner format (00 + 18 digits) — normalised automatically.
    /// </summary>
    [Required]
    public string Sscc { get; init; } = null!;

    [Range(1, int.MaxValue)]
    public int Quantity { get; init; }

    [MaxLength(100)]
    public string? BatchNumber { get; init; }

    public DateOnly? BestBeforeDate { get; init; }
}
