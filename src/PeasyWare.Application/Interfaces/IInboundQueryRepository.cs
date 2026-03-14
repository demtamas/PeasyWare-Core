using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IInboundQueryRepository
{
    IEnumerable<ActivatableInboundDto> GetActivatableInbounds();
    IEnumerable<InboundLineDto> GetReceivableLines(string inboundRef);
    SsccValidationDto ValidateSsccForInbound(string externalRef, string stagingBin);

}
