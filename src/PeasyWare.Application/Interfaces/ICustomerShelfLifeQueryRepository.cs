using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface ICustomerShelfLifeQueryRepository
{
    IReadOnlyList<CustomerShelfLifeRequirementDto> GetAll();
}
