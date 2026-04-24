using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Logging;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Errors;
using PeasyWare.Infrastructure.Repositories;
using PeasyWare.Infrastructure.Settings;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Bootstrap;

public static class AppStartup
{
    private static SqlConnectionFactory? _factory;
    private static IErrorMessageResolver _messageResolver = null!;

    public static AppRuntime Initialize()
    {
        var bootstrap = BootstrapLoader.Load();

        _factory = new SqlConnectionFactory(
            bootstrap.ConnectionString);

        _messageResolver =
            new SqlErrorMessageResolver(_factory);

        var settings =
            new SettingsLoader(_factory).Load();

        if (!settings.LoginEnabled)
            throw new InvalidOperationException(
                "Login is disabled by system policy.");

        ILogger logger = settings.LoggingEnabled
            ? new InfrastructureLogger(settings, _factory)
            : new NoOpLogger();

        // --------------------------------------------------
        // SYSTEM SESSION
        // --------------------------------------------------

        var bootstrapSession = new SessionContext(
            sessionId: Guid.Empty,
            userId: 0,
            username: "SYSTEM",
            displayName: "SYSTEM",
            sourceApp: "PeasyWare.System",
            sourceClient: Environment.MachineName,
            sourceIp: null,
            correlationId: null,
            osInfo: Environment.OSVersion.ToString(),
            roleName: "system",
            uiMode: UiMode.Minimal,
            sessionTimeoutMinutes: 480
        );

        // --------------------------------------------------
        // STATELESS QUERY REPOS
        // --------------------------------------------------

        var userSecurityRepo =
            new SqlUserSecurityRepository(
                _factory,
                _messageResolver,
                logger);

        var sessionQueryRepo =
            new SqlSessionQueryRepository(_factory, bootstrapSession);

        var sessionDetailsRepo =
            new SqlSessionDetailsRepository(_factory);

        var userQueryRepo =
            new SqlUserQueryRepository(_factory, bootstrapSession);

        var settingsQueryRepo =
            new SqlSettingsQueryRepository(_factory, bootstrapSession);

        // --------------------------------------------------
        // SESSION COMMAND
        // --------------------------------------------------

        var sessionCommandRepo =
            new SqlSessionCommandRepository(
                _factory,
                bootstrapSession,
                _messageResolver,
                logger);

        var sessionGuard =
            new SessionGuard(sessionCommandRepo);

        // --------------------------------------------------
        // AUTH
        // --------------------------------------------------

        var authService =
            new AuthService(
                new SqlLoginRepository(_factory, _messageResolver),
                userSecurityRepo,
                logger);

        // --------------------------------------------------
        // FACTORY
        // --------------------------------------------------

        var repositories =
            new RepositoryFactory(
                _factory,
                _messageResolver,
                logger,
                sessionGuard,
                bootstrapSession);

        // --------------------------------------------------
        // RUNTIME
        // --------------------------------------------------

        return new AppRuntime(
            settings,
            logger,
            authService,
            userSecurityRepo,
            sessionQueryRepo,
            sessionDetailsRepo,
            userQueryRepo,
            settingsQueryRepo,
            sessionGuard,
            _factory,
            _messageResolver,
            repositories);
    }

    public static void Shutdown()
    {
        //CorrelationContext.Clear();
    }
}
