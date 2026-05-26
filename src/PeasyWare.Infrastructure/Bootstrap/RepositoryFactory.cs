using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Repositories;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Infrastructure.Bootstrap;

public sealed class RepositoryFactory
{
    private readonly SqlConnectionFactory  _factory;
    private readonly IErrorMessageResolver _resolver;
    private readonly ILogger               _logger;
    private readonly SessionGuard          _sessionGuard;
    private readonly SessionContext        _systemSession;
    private          SessionContext        _mutableSystemSession;
    private          SessionContext        SystemSession => _mutableSystemSession;

    public RepositoryFactory(
        SqlConnectionFactory  factory,
        IErrorMessageResolver resolver,
        ILogger               logger,
        SessionGuard          sessionGuard,
        SessionContext        systemSession)
    {
        _factory              = factory;
        _resolver             = resolver;
        _logger               = logger;
        _sessionGuard         = sessionGuard;
        _systemSession        = systemSession;
        _mutableSystemSession = systemSession;
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

    /// <summary>Sessionless overload for API use — uses system session.</summary>
    public IInboundCommandRepository CreateInboundCommand()
        => CreateInboundCommand(SystemSession);

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

    public IInventoryCommandRepository CreateInventoryCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlInventoryCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);
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

    /// <summary>Sessionless overload for API use — uses system session.</summary>
    public IOutboundCommandRepository CreateOutboundCommand()
        => CreateOutboundCommand(SystemSession);

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

    public IWarehouseTaskQueryRepository CreateWarehouseTaskQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlWarehouseTaskQueryRepository(_factory, session, _resolver, _logger, _sessionGuard);
    }

    // --------------------------------------------------
    // SKU (API)
    // --------------------------------------------------

    public ISkuCommandRepository CreateSkuCommand()
        => new SqlSkuCommandRepository(_factory, SystemSession, _resolver, _logger, _sessionGuard);

    public ISkuCommandRepository CreateSkuCommand(SessionContext session)
        => new SqlSkuCommandRepository(_factory, session, _resolver, _logger, _sessionGuard);

    public ISkuQueryRepository CreateSkuQuery()
        => new SqlSkuQueryRepository(_factory, SystemSession);

    public ISkuQueryRepository CreateSkuQuery(SessionContext session)
        => new SqlSkuQueryRepository(_factory, session);

    public IAuditQueryRepository CreateAuditQuery(SessionContext session)
        => new SqlAuditQueryRepository(_factory, session);

    // --------------------------------------------------
    // PARTIES
    // --------------------------------------------------

    public IPartyQueryRepository CreatePartyQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlPartyQueryRepository(_factory, session);
    }

    public IPartyCommandRepository CreatePartyCommand(SessionContext session)
    {
        BindSession(session);
        return new SqlPartyCommandRepository(_factory, session);
    }

    // --------------------------------------------------
    // MOVEMENTS
    // --------------------------------------------------

    public IMovementQueryRepository CreateMovementQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlMovementQueryRepository(_factory, session);
    }

    // --------------------------------------------------
    // EVENT LOG
    // --------------------------------------------------

    public IEventLogQueryRepository CreateEventLogQuery(SessionContext session)
    {
        BindSession(session);
        return new SqlEventLogQueryRepository(_factory, session);
    }

    // --------------------------------------------------
    // SHIPMENT MANIFEST
    // --------------------------------------------------

    public IShipmentManifestRepository CreateShipmentManifest(SessionContext session)
    {
        BindSession(session);
        return new SqlShipmentManifestRepository(_factory, session);
    }

    /// <summary>
    /// Replaces the system session used by sessionless overloads.
    /// Called by AppStartup.InitializeForApi() after the api user
    /// is resolved from the database.
    /// </summary>
    internal void UpdateSystemSession(SessionContext session)
        => _mutableSystemSession = session;
}
