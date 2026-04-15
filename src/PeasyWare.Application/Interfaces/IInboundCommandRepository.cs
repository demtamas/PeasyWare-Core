using PeasyWare.Application;

namespace PeasyWare.Application.Interfaces;

public interface IInboundCommandRepository
{
    OperationResult ActivateInbound(int inboundId);

    OperationResult ActivateInboundByRef(string inboundRef);

    OperationResult ReceiveInboundLine(
        int inboundLineId,
        int receivedQty,
        string stagingBinCode,
        int? inboundExpectedUnitId = null,
        string? externalRef = null,
        string? batchNumber = null,
        DateTime? bestBeforeDate = null,
        Guid? claimToken = null);

    OperationResult ReverseInboundReceipt(
        int receiptId,
        string? reasonCode = null,
        string? reasonText = null);
}
