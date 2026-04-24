using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IInboundQueryRepository
{
    InboundSummaryDto GetInboundSummary(string inboundRef);

    int GetOutstandingSsccCount(string inboundRef);

    IEnumerable<ActivatableInboundDto> GetActivatableInbounds();

    IEnumerable<InboundLineDto> GetReceivableLines(string inboundRef);

    SsccValidationDto ValidateSsccForInbound(
        string externalRef,
        string stagingBin,
        DateOnly? scannedBestBefore = null,
        string? scannedBatch = null);

    IEnumerable<InboundReceiptDto> GetReceivableReceipts(string inboundRef);

    InboundLineByEanDto? GetReceivableLineByEan(string inboundRef, string ean);
}
