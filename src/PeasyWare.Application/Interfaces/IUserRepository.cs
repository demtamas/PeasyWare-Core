using PeasyWare.Domain;

namespace PeasyWare.Application.Interfaces;

public interface IUserRepository
{
    User? GetByUsername(string username);
}
