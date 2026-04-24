using System.ComponentModel.DataAnnotations;

namespace PeasyWare.API.Requests;

public sealed class CreateOrderRequest
{
    [Required, MaxLength(50)]
    public string OrderRef { get; init; } = null!;

    [Required]
    public string CustomerPartyCode { get; init; } = null!;

    public string? HaulierPartyCode { get; init; }

    public DateOnly? RequiredDate { get; init; }

    public string? Notes { get; init; }

    [Required, MinLength(1)]
    public List<OrderLineItem> Lines { get; init; } = new();
}

public sealed class OrderLineItem
{
    [Range(1, 999)]
    public int LineNo { get; init; }

    [Required, MaxLength(50)]
    public string SkuCode { get; init; } = null!;

    [Range(1, int.MaxValue)]
    public int OrderedQty { get; init; }

    public string? RequestedBatch { get; init; }

    public DateOnly? RequestedBbe { get; init; }

    public string? Notes { get; init; }
}

public sealed class CreateShipmentRequest
{
    [Required, MaxLength(50)]
    public string ShipmentRef { get; init; } = null!;

    [Required]
    public string HaulierPartyCode { get; init; } = null!;

    public string? VehicleRef { get; init; }

    public DateTime? PlannedDeparture { get; init; }

    public string? Notes { get; init; }
}

public sealed class AddOrderToShipmentRequest
{
    [Required]
    public string OrderRef { get; init; } = null!;
}
