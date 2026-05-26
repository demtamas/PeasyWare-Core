using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IOutboundCommandRepository
{
    // ── API creation methods ──────────────────────────────────────────────

    OperationResult CreateOrder(
        string orderRef,
        string customerPartyCode,
        string? haulierPartyCode   = null,
        string? deliveryPartyCode  = null,
        DateTime? requiredDate     = null,
        string? notes              = null,
        List<OrderLineDto> lines   = null!);

    OperationResult CreateShipment(
        string shipmentRef,
        string haulierPartyCode,
        string? vehicleRef = null,
        DateTime? plannedDeparture = null,
        string? notes = null);

    OperationResult AddOrderToShipment(
        string shipmentRef,
        string orderRef);

    OperationResult CancelShipment(
        string  shipmentRef,
        string? reason = null);

    // ── Allocation management ────────────────────────────────────────────

    OperationResult AllocateOrder(int outboundOrderId, bool allowPartial = false);

    OperationResult DeallocateOrder(int outboundOrderId);

    /// <summary>
    /// Hard-cancels a NEW order (no allocations, nothing in flight).
    /// Refuses if any line is beyond NEW status.
    /// </summary>
    OperationResult CancelOrder(int outboundOrderId);

    // ── CLI / warehouse methods ─────────────────────────────────────────

    PickTaskResult CreatePickTask(int allocationId, string? destinationBinCode);

    OperationResult ConfirmPickTask(int taskId, string scannedBinCode, string scannedSscc);

    OperationResult CancelAllocation(int allocationId, string? reason = null);

    OperationResult ReallocateLine(int outboundLineId);

    LoadConfirmResult ConfirmLoad(int outboundOrderId, int shipmentId);

    ShipResult Ship(int shipmentId, string vehicleRef);
}
