namespace PeasyWare.Application.Interfaces;

public interface IUserCommandRepository
{
    OperationResult EnableUser(int userId);
    OperationResult DisableUser(int userId);

    // Logs out ALL active sessions for that user
    OperationResult LogoutUserEverywhere(
        int userId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null);

    OperationResult CreateUser(
    string username,
    string displayName,
    string roleName,
    string email,
    string password);
    OperationResult ResetPasswordAsAdmin(int targetUserId, string newPassword);


}
