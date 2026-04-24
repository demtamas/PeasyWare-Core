using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ISkuQueryRepository
{
    SkuDto? GetByCode(string skuCode);
}
