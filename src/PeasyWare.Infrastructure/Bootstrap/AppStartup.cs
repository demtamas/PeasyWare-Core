using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Logging;
using PeasyWare.Infrastructure.Errors;
using PeasyWare.Infrastructure.Logging;
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
        _factory = new SqlConnectionFactory(bootstrap.ConnectionString);

        // 🔹 Centralised message resolver
        _messageResolver = new SqlErrorMessageResolver(_factory);

        var settings = new SettingsLoader(_factory).Load();

        if (!settings.LoginEnabled)
            throw new InvalidOperationException("Login is disabled by system policy.");

        ILogger logger = settings.LoggingEnabled
            ? new InfrastructureLogger(settings, _factory)
            : new NoOpLogger();

        // ─────────────────────────────
        // PRE-SESSION ONLY
        // ─────────────────────────────

        var userSecurityRepo =
            new SqlUserSecurityRepository(
                _factory,
                _messageResolver,
                logger);

        var sessionQueryRepo =
            new SqlSessionQueryRepository(_factory);

        var sessionDetailsRepo =
            new SqlSessionDetailsRepository(_factory);

        var userQueryRepo =
            new SqlUserQueryRepository(_factory);

        var authService = new AuthService(
            new SqlLoginRepository(_factory),
            userSecurityRepo,
            logger);

        return new AppRuntime(
            settings,
            logger,
            authService,
            userSecurityRepo,
            sessionQueryRepo,
            sessionDetailsRepo,
            userQueryRepo,
            _factory,
            _messageResolver   // 🔹 expose resolver
        );
    }

    public static void Shutdown()
    {
        CorrelationContext.Clear();
    }
}