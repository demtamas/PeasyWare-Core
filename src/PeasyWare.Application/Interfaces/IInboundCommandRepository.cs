using PeasyWare.Application;

namespace PeasyWare.Application.Interfaces;

public interface IInboundCommandRepository
{
    // ── API creation methods ──────────────────────────────────────────────

    OperationResult CreateInbound(
        string    inboundRef,
        string    supplierPartyCode,
        string?   haulierPartyCode  = null,
        DateTime? expectedArrivalAt = null);

    OperationResult AddInboundLine(
        string    inboundRef,
        string    skuCode,
        int       expectedQty,
        string?   batchNumber        = null,
        DateTime? bestBeforeDate     = null,
        string    arrivalStockStatus = "AV");

    OperationResult AddExpectedUnit(
        string    inboundRef,
        string    sscc,
        int       quantity,
        string?   batchNumber    = null,
        DateTime? bestBeforeDate = null);

    // ── CLI / receiving methods ───────────────────────────────────────────

    OperationResult ActivateInbound(int inboundId);

    OperationResult ActivateInboundByRef(string inboundRef);

    OperationResult ReceiveInboundLine(
        int       inboundLineId,
        int       receivedQty,
        string    stagingBinCode,
        int?      inboundExpectedUnitId = null,
        string?   externalRef          = null,
        string?   batchNumber          = null,
        DateTime? bestBeforeDate       = null,
        Guid?     claimToken           = null);

    OperationResult ReverseInboundReceipt(
        int     receiptId,
        string? reasonCode = null,
        string? reasonText = null);
}
