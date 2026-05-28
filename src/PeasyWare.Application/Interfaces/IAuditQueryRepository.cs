using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IAuditQueryRepository
{
    IReadOnlyList<SkuChangeLogDto> GetSkuChanges(
        string? skuCode  = null,
        DateOnly? from   = null,
        DateOnly? to     = null,
        int top          = 200);

    IReadOnlyList<LocationChangeLogDto> GetLocationChanges(
        string?   binCode = null,
        DateOnly? from    = null,
        DateOnly? to      = null,
        int       top     = 500);
}
