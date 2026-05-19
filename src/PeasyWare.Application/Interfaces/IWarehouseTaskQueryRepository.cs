using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IWarehouseTaskQueryRepository
{
    IEnumerable<WarehouseTaskDto> GetTasks(bool activeOnly = true);
    IEnumerable<WarehouseTaskDto> GetTasksByUnit(string sscc);
}
