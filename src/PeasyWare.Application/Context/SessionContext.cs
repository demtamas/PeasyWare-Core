namespace PeasyWare.Application.Contexts;

public sealed class SessionContext
{
    public Guid SessionId { get; }
    public int UserId { get; }
    public string Username { get; }

    public SessionContext(
        Guid sessionId,
        int userId,
        string username)
    {
        SessionId = sessionId;
        UserId = userId;
        Username = username;
    }
}
