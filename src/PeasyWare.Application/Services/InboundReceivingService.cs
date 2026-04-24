using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;

namespace PeasyWare.Application.Services;

public sealed class InboundReceivingService
{
    private readonly IInboundQueryRepository _queryRepo;
    private readonly IInboundCommandRepository _commandRepo;
    private readonly IErrorMessageResolver _resolver;

    public InboundReceivingService(
        IInboundQueryRepository queryRepo,
        IInboundCommandRepository commandRepo,
        IErrorMessageResolver resolver)
    {
        _queryRepo = queryRepo;
        _commandRepo = commandRepo;
        _resolver = resolver;
    }

    public SsccValidationDto ValidateSscc(
        string externalRef,
        string bin,
        DateOnly? scannedBestBefore = null,
        string? scannedBatch = null)
    {
        return _queryRepo.ValidateSsccForInbound(
            externalRef,
            bin,
            scannedBestBefore,
            scannedBatch);
    }

    public OperationResult ConfirmSscc(
        int inboundExpectedUnitId,
        string externalRef,
        string bin,
        Guid claimToken,
        string? batchNumber = null,
        DateTime? bestBeforeDate = null)
    {
        return _commandRepo.ReceiveInboundLine(
            inboundLineId: 0,
            receivedQty: 0,
            stagingBinCode: bin,
            inboundExpectedUnitId: inboundExpectedUnitId,
            externalRef: externalRef,
            batchNumber: batchNumber,
            bestBeforeDate: bestBeforeDate,
            claimToken: claimToken
        );
    }

    // This might be the future, where we first do a preview to get the friendly message and other details, then confirm the receive.
    private SsccValidationDto MapToDto(
        ReceivePreviewResult preview,
        string friendlyMessage)
    {
        return new SsccValidationDto
        {
            Success = preview.Success,
            FriendlyMessage = friendlyMessage,

            InboundLineId = preview.InboundLineId ?? 0,
            InboundRef = preview.InboundRef ?? "",
            HeaderStatus = preview.HeaderStatus ?? "",
            LineState = preview.LineState ?? "",

            SkuCode = preview.SkuCode ?? "",
            SkuDescription = preview.SkuDescription ?? "",

            ExpectedUnitQty = preview.ExpectedUnitQty ?? 0,
            LineExpectedQty = preview.LineExpectedQty ?? 0,
            LineReceivedQty = preview.LineReceivedQty ?? 0,

            OutstandingBefore = preview.OutstandingBefore ?? 0,
            OutstandingAfter = preview.OutstandingAfter ?? 0,

            BatchNumber = preview.BatchNumber,
            BestBeforeDate = preview.BestBeforeDate,

            ClaimToken = preview.ClaimToken,
            ClaimExpiresAt = preview.ClaimExpiresAt
        };
    }
}