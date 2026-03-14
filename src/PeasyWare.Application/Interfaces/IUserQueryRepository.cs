using PeasyWare.Application.Dto;

namespace PeasyWare.Application.Interfaces;

public interface IUserQueryRepository
{
    IReadOnlyList<UserSummaryDto> GetUsers(string? search = null);
    IEnumerable<RoleDto> GetRoles();
}
