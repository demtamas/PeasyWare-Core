using PeasyWare.Application.Interfaces;
using PeasyWare.Domain;

namespace PeasyWare.Infrastructure.Repositories;

public sealed class InMemoryUserRepository : IUserRepository
{
    private static readonly List<User> _users =
    [
        new User(1, "admin", true),
        new User(2, "disabled", false)
    ];

    public User? GetByUsername(string username)
        => _users.FirstOrDefault(u =>
            u.Username.Equals(username, StringComparison.OrdinalIgnoreCase));
}
