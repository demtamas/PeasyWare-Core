namespace PeasyWare.Domain;

public sealed class User
{
    public int Id { get; }
    public string Username { get; }
    public bool IsActive { get; }

    public User(int id, string username, bool isActive)
    {
        Id = id;
        Username = username;
        IsActive = isActive;
    }
}
