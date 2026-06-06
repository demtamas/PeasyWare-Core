using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IZoneRepository
{
    // Query
    IReadOnlyList<ZoneDto> GetZones(bool includeInactive = false);

    // Command
    OperationResult CreateZone(string zoneCode, string zoneName, string? description = null);
    OperationResult UpdateZone(string zoneCode, string? zoneName = null, string? description = null, bool clearDesc = false);
    OperationResult DeactivateZone(string zoneCode);
    OperationResult ReactivateZone(string zoneCode);
    OperationResult DeleteZone(string zoneCode);
}
