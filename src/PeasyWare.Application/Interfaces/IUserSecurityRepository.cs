using PeasyWare.Application;

namespace PeasyWare.Application.Interfaces;

public interface IUserSecurityRepository
{
    OperationResult ChangePassword(
        string username,
        string newPassword);
}
