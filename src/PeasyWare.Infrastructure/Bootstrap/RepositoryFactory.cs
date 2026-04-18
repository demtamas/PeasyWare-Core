using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Repositories;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Bootstrap;

public sealed class RepositoryFactory
{
    private readonly SqlConnectionFactory _factory;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger _logger;
    private readonly SessionGuard _sessionGuard;

    public RepositoryFactory(
        SqlConnectionFactory factory,
        IErrorMessageResolver resolver,
        ILogger logger,
        SessionGuard sessionGuard)
    {
        _factory = factory;
        _resolver = resolver;
        _logger = logger;
        _sessionGuard = sessionGuard;
    }

    private void BindSession(SessionContext session) =>
        _logger.SetSession(session);

    // --------------------------------------------------
    // SESSION
    // --------------------------------------------------

    public ISessionCommandRepository CreateSessionCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlSessionCommandRepository(_factory, session, _resolver, _logger);
    }

    // --------------------------------------------------
    // USER
    // --------------------------------------------------

    public IUserCommandRepository CreateUserCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlUserCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);
    }

    public IUserQueryRepository CreateUserQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlUserQueryRepository(_factory, session);
    }

    // --------------------------------------------------
    // INBOUND
    // --------------------------------------------------

    public IInboundCommandRepository CreateInboundCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlInboundCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);
    }

    public IInboundQueryRepository CreateInboundQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlInboundQueryRepository(_factory, session, _resolver);
    }

    // --------------------------------------------------
    // INVENTORY
    // --------------------------------------------------

    public IInventoryQueryRepository CreateInventoryQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlInventoryQueryRepository(_factory, session);
    }

    // --------------------------------------------------
    // OUTBOUND
    // --------------------------------------------------

    public IOutboundQueryRepository CreateOutboundQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlOutboundQueryRepository(_factory, session);
    }

    public IOutboundCommandRepository CreateOutboundCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlOutboundCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);
    }

    // --------------------------------------------------
    // SETTINGS
    // --------------------------------------------------

    public ISettingsCommandRepository CreateSettingsCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlSettingsCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);
    }

    public ISettingsQueryRepository CreateSettingsQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlSettingsQueryRepository(_factory, session);
    }

    // --------------------------------------------------
    // WAREHOUSE TASKS
    // --------------------------------------------------

    public IWarehouseTaskCommandRepository CreateWarehouseTaskCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlWarehouseTaskCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);
    }
}
