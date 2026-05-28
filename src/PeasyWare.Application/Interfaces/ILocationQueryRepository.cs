using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ILocationQueryRepository
{
    IReadOnlyList<LocationDto> GetLocations(
        bool   withStockOnly    = true,
        string? storageTypeCode = null,
        string? zoneCode        = null,
        string? search          = null);

    IReadOnlyList<string> GetStorageTypeCodes();
    IReadOnlyList<string> GetZoneCodes();
}
