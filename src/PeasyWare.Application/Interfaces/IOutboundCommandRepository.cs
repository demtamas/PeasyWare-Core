using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IOutboundCommandRepository
{
    // ── API creation methods ──────────────────────────────────────────────

    OperationResult CreateOrder(
        string             orderRef,
        string             customerPartyCode,
        string?            haulierPartyCode = null,
        DateTime?          requiredDate     = null,
        string?            notes            = null,
        List<OrderLineDto> lines            = null!);

    OperationResult CreateShipment(
        string    shipmentRef,
        string    haulierPartyCode,
        string?   vehicleRef       = null,
        DateTime? plannedDeparture = null,
        string?   notes            = null);

    OperationResult AddOrderToShipment(
        string shipmentRef,
        string orderRef);

    // ── CLI / warehouse methods ─────────────────────────────────────────

    PickTaskResult   CreatePickTask(int allocationId, string? destinationBinCode);

    OperationResult  ConfirmPickTask(int taskId, string scannedBinCode, string scannedSscc);

    LoadConfirmResult ConfirmLoad(int outboundOrderId, int shipmentId);

    ShipResult       Ship(int shipmentId);
}
