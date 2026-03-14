using PeasyWare.Application;

namespace PeasyWare.Application.Interfaces;

public interface IInboundCommandRepository
{
    OperationResult ActivateInbound(int inboundId);

    OperationResult ReceiveInboundLine(
        int inboundLineId,
        int receivedQty,
        string stagingBinCode,
        int? inboundExpectedUnitId = null,   // ✅ NEW
        string? externalRef = null,
        string? batchNumber = null,
        DateTime? bestBeforeDate = null,
        Guid? claimToken = null);
}
