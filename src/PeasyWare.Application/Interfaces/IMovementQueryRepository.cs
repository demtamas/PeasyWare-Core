using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IMovementQueryRepository
{
    IReadOnlyList<MovementDto> GetMovements(
        string?   movementTypeFilter = null,
        string?   ssccFilter         = null,
        DateTime? fromDate           = null,
        DateTime? toDate             = null,
        int       top                = 500);
}
