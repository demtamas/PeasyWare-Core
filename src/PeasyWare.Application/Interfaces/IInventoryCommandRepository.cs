using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IInventoryCommandRepository
{
    /// <summary>
    /// Updates the stock status (AV/QC/BL/DM) for a list of SSCCs in one transaction.
    /// Returns the number of units affected and a result code.
    /// </summary>
    OperationResult UpdateStockStatus(
        IEnumerable<string> ssccs,
        string              newStatusCode,
        string?             reason      = null);
}
