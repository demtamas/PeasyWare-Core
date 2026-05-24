using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IPartyQueryRepository
{
    IReadOnlyList<PartyDto> GetParties(string? roleFilter = null, bool includeInactive = false);
    PartyDto? GetParty(int partyId);
}
