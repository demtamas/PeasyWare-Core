namespace PeasyWare.Application.Contexts;

public sealed class SessionContext
{
    public Guid SessionId { get; }
    public int UserId { get; }
    public string Username { get; }
    public string DisplayName { get; }
    public string RoleName { get; }
    public UiMode UiMode { get; }

    public string SourceApp { get; }
    public string SourceClient { get; }
    public string? SourceIp { get; }
    public Guid? CorrelationId { get; }

    public int SessionTimeoutMinutes { get; }

    private readonly IReadOnlySet<string> _permissions;

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
        string? roleName,
        UiMode uiMode,
        int sessionTimeoutMinutes,
        IReadOnlySet<string>? permissions = null)
    {
        SessionId = sessionId;
        UserId = userId;
        Username = username;
        DisplayName = displayName;
        RoleName = roleName ?? "operator";
        UiMode = uiMode;

        SourceApp = sourceApp;
        SourceClient = sourceClient;
        SourceIp = sourceIp;
        CorrelationId = correlationId;
        SessionTimeoutMinutes = sessionTimeoutMinutes;
        _permissions = permissions ?? new HashSet<string>();
    }

    // --------------------------------------------------
    // RBAC (Phase 2d) - mirrors auth.fn_has_permission on
    // the DB side. The permission set is loaded once at
    // login (auth.v_user_permissions) and is immutable for
    // the lifetime of the session; a role/permission change
    // takes effect on next login, same as RoleName/UiMode.
    // --------------------------------------------------
    public bool HasPermission(string permissionKey)
        => _permissions.Contains(permissionKey);
}
