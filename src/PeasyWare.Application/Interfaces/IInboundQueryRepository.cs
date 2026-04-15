using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IInboundQueryRepository
{
    InboundSummaryDto GetInboundSummary(string inboundRef);

    int GetOutstandingSsccCount(string inboundRef);

    IEnumerable<ActivatableInboundDto> GetActivatableInbounds();

    SsccValidationDto ValidateSsccForInbound(
        string externalRef,
        string stagingBin);

    IEnumerable<InboundReceiptDto> GetReceivableReceipts(string inboundRef);
}
