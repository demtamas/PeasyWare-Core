using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IOutboundQueryRepository
{
    IReadOnlyList<OutboundOrderSummaryDto> GetPickableOrders();

    OutboundOrderSummaryDto? GetOrderSummary(string orderRef);

    IReadOnlyList<OutboundAllocationDto> GetAllocationsForOrder(int outboundOrderId);

    IReadOnlyList<ShipmentSummaryDto> GetActiveShipments();

    ShipmentSummaryDto? GetShipmentByRef(string shipmentRef);

    IReadOnlyList<OutboundOrderSummaryDto> GetOrdersOnShipment(int shipmentId);
}
