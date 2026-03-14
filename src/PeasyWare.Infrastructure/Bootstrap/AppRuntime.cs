using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
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

    // ───────────────
    // Shared infrastructure
    // ───────────────

    public SqlConnectionFactory ConnectionFactory { get; }
    public IErrorMessageResolver ErrorMessageResolver { get; }

    //public ISessionCommandRepository SessionCommandRepository { get; set; }

    internal AppRuntime(
        RuntimeSettings settings,
        ILogger logger,
        AuthService authService,
        IUserSecurityRepository userSecurityRepository,
        ISessionQueryRepository sessionQueryRepository,
        ISessionDetailsRepository sessionDetailsRepository,
        IUserQueryRepository userQueryRepository,
        SqlConnectionFactory connectionFactory,
        IErrorMessageResolver errorMessageResolver)
    {
        Settings = settings;
        Logger = logger;

        AuthService = authService;
        UserSecurityRepository = userSecurityRepository;

        SessionQueryRepository = sessionQueryRepository;
        SessionDetailsRepository = sessionDetailsRepository;

        UserQueryRepository = userQueryRepository;

        ConnectionFactory = connectionFactory;
        ErrorMessageResolver = errorMessageResolver;
    }
}