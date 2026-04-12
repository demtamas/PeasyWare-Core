using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Errors;
using PeasyWare.Infrastructure.Settings;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Bootstrap;

public sealed class AppRuntime
{
    public RuntimeSettings Settings { get; }
    public ILogger Logger { get; }

    // ───────────────
    // Pre-session only
    // ───────────────

    public AuthService AuthService { get; }
    public IUserSecurityRepository UserSecurityRepository { get; }
    public ISessionQueryRepository SessionQueryRepository { get; }
    public ISessionDetailsRepository SessionDetailsRepository { get; }
    public IUserQueryRepository UserQueryRepository { get; }
    public ISettingsQueryRepository SettingsQueryRepository { get; }

    public RepositoryFactory Repositories { get; }
    public SessionGuard SessionGuard { get; }

    // ───────────────
    // Shared infrastructure
    // ───────────────

    public SqlConnectionFactory ConnectionFactory { get; }
    public IErrorMessageResolver ErrorMessageResolver { get; }

    internal AppRuntime(
        RuntimeSettings settings,
        ILogger logger,
        AuthService authService,
        IUserSecurityRepository userSecurityRepository,
        ISessionQueryRepository sessionQueryRepository,
        ISessionDetailsRepository sessionDetailsRepository,
        IUserQueryRepository userQueryRepository,
        ISettingsQueryRepository settingsQueryRepository,
        SessionGuard sessionGuard,
        SqlConnectionFactory connectionFactory,
        IErrorMessageResolver errorMessageResolver,
        RepositoryFactory repositories)
    {
        Settings = settings;
        Logger = logger;

        AuthService = authService;
        UserSecurityRepository = userSecurityRepository;
        SessionQueryRepository = sessionQueryRepository;
        SessionDetailsRepository = sessionDetailsRepository;
        UserQueryRepository = userQueryRepository;
        SettingsQueryRepository = settingsQueryRepository;

        SessionGuard = sessionGuard;

        ConnectionFactory = connectionFactory;
        ErrorMessageResolver = errorMessageResolver;

        Repositories = repositories;
    }
}