namespace PeasyWare.Application.Contexts;

public sealed class SessionContext
{
    public Guid SessionId { get; }
    public int UserId { get; }
    public string Username { get; }
    public string DisplayName { get; }

    public string SourceApp { get; }
    public string SourceClient { get; }
    public string? SourceIp { get; }
    public Guid? CorrelationId { get; }

    public int SessionTimeoutMinutes { get; }

    public SessionContext(
        Guid sessionId,
        int userId,
        string username,
        string displayName,
        string sourceApp,
        string sourceClient,
        string? sourceIp,
        Guid? correlationId,
        string osInfo,
        int sessionTimeoutMinutes)
    {
        SessionId = sessionId;
        UserId = userId;
        Username = username;
        DisplayName = displayName;

        SourceApp = sourceApp;
        SourceClient = sourceClient;
        SourceIp = sourceIp;
        CorrelationId = correlationId;
        SessionTimeoutMinutes = sessionTimeoutMinutes;
    }
}
