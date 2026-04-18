using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IOutboundQueryRepository
{
    IReadOnlyList<OutboundOrderSummaryDto> GetPickableOrders();

    OutboundOrderSummaryDto? GetOrderSummary(string orderRef);

    IReadOnlyList<OutboundAllocationDto> GetAllocationsForOrder(int outboundOrderId);
}
