using PeasyWare.Application;
using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IPartyCommandRepository
{
    OperationResult CreateParty(
        string  partyCode,
        string  legalName,
        string  displayName,
        string? countryCode = null,
        string? taxId       = null,
        string? roles       = null);

    OperationResult UpdateParty(
        int     partyId,
        string  legalName,
        string  displayName,
        string? countryCode = null,
        string? taxId       = null,
        bool    isActive    = true,
        string? roles       = null);
}
