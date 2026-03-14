using PeasyWare.Domain;

namespace PeasyWare.Application.Interfaces;

public interface ILoginRepository
{
    LoginResult Login(
        string username,
        string? password,
        LoginContext context);
}
