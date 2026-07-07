using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IClientRepository
{
    IReadOnlyList<ClientDto> GetClients(bool includeInactive = false);
    OperationResult CreateClient(string clientName, int? sessionTimeoutMinutes = null, int? maxConcurrentSessions = null, string? description = null);
    OperationResult UpdateClient(string clientName, int? sessionTimeoutMinutes = null, bool clearTimeout = false, int? maxConcurrentSessions = null, bool clearMaxSessions = false, string? description = null, bool clearDesc = false);
    OperationResult DeactivateClient(string clientName);
    OperationResult ReactivateClient(string clientName);
}
