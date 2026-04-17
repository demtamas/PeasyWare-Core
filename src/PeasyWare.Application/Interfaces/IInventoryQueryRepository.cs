using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IInventoryQueryRepository
{
    InventoryUnitDto? GetInventoryUnitByExternalRef(string externalRef);

    int GetUnitsAwaitingPutawayCount();

    ActiveInventoryDto? GetActiveInventoryBySscc(string sscc);

    IReadOnlyList<ActiveInventoryDto> GetActiveInventoryByBin(string binCode);

    bool BinExists(string binCode);
}
