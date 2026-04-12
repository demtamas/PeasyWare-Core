using PeasyWare.Application;
using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IWarehouseTaskCommandRepository
{
    PutawayTaskResult CreatePutawayTask(int inventoryUnitId);

    OperationResult ConfirmPutawayTask(int taskId, string destinationBinCode);
}