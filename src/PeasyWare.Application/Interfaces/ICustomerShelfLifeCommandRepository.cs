namespace PeasyWare.Application.Interfaces;

public interface ICustomerShelfLifeCommandRepository
{
    OperationResult SetRequirement(string customerPartyCode, string skuCode, int minimumRemainingShelfLifeDays);
    OperationResult DeleteRequirement(string customerPartyCode, string skuCode);
}
