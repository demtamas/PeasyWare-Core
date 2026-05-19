using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IOutboundQueryRepository
{
    /// <summary>Active orders — NEW, ALLOCATED, PICKING, PICKED, LOADED (default view).</summary>
    IReadOnlyList<OutboundOrderSummaryDto> GetOutstandingOrders();

    /// <summary>Departed / shipped orders only.</summary>
    IReadOnlyList<OutboundOrderSummaryDto> GetDepartedOrders();

    /// <summary>All orders regardless of status.</summary>
    IReadOnlyList<OutboundOrderSummaryDto> GetAllOrders();

    IReadOnlyList<OutboundOrderSummaryDto> GetPickableOrders();

    OutboundOrderSummaryDto? GetOrderSummary(string orderRef);

    /// <summary>Lines for a single order. Used by the Lines tab in OrderDetailForm.</summary>
    IReadOnlyList<OutboundOrderLineDto> GetOrderLines(int outboundOrderId);

    IReadOnlyList<OutboundAllocationDto> GetAllocationsForOrder(int outboundOrderId);

    IReadOnlyList<ShipmentSummaryDto> GetActiveShipments();
    IReadOnlyList<ShipmentSummaryDto> GetShippedShipments();
    IReadOnlyList<ShipmentSummaryDto> GetAllShipments();

    ShipmentSummaryDto? GetShipmentByRef(string shipmentRef);

    IReadOnlyList<OutboundOrderSummaryDto> GetOrdersOnShipment(int shipmentId);
}
