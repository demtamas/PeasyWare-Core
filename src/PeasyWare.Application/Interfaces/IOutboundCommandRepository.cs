using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IOutboundCommandRepository
{
    PickTaskResult CreatePickTask(int allocationId, string? destinationBinCode);

    OperationResult ConfirmPickTask(int taskId, string scannedBinCode, string scannedSscc);

    LoadConfirmResult ConfirmLoad(int outboundOrderId, int shipmentId);

    ShipResult Ship(int shipmentId);
}
