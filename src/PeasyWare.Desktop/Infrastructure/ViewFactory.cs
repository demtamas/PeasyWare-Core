using PeasyWare.Application.Contexts;
using PeasyWare.Desktop.Views.Inbound;
using PeasyWare.Desktop.Views.Inventory;
using PeasyWare.Desktop.Views.Movements;
using PeasyWare.Desktop.Views.Parties;
using PeasyWare.Desktop.Views.Logs;
using PeasyWare.Desktop.Views.Materials;
using PeasyWare.Desktop.Views.Sessions;
using PeasyWare.Desktop.Views.Settings;
using PeasyWare.Desktop.Views.Shipments;
using PeasyWare.Desktop.Views.Users;
using PeasyWare.Desktop.Views.Warehouse;
using PeasyWare.Infrastructure.Bootstrap;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Infrastructure;

public sealed class ViewFactory
{
    private readonly AppRuntime _runtime;

    public ViewFactory(AppRuntime runtime)
    {
        _runtime = runtime;
    }

    public UserControl CreateSessionsView(SessionContext session)
    {
        var commandRepo =
            _runtime.Repositories.CreateSessionCommand(session);

        return new SessionsView(
            session.SessionId,
            _runtime.SessionQueryRepository,
            commandRepo,
            _runtime.SessionDetailsRepository);
    }

    public UserControl CreateUsersView(SessionContext session)
    {
        var userCommandRepo =
            _runtime.Repositories.CreateUserCommand(session);

        var sessionCommandRepo =
            _runtime.Repositories.CreateSessionCommand(session);

        return new UsersView(
            session.SessionId,
            _runtime.UserQueryRepository,
            userCommandRepo,
            sessionCommandRepo);
    }

    public UserControl CreateSettingsView(SessionContext session)
    {
        var commandRepo =
            _runtime.Repositories.CreateSettingsCommand(session);

        return new SettingsView(
            session.SessionId,
            _runtime.SettingsQueryRepository,
            commandRepo);
    }

    public UserControl CreateInventoryView(SessionContext session)
    {
        var queryRepo   = _runtime.Repositories.CreateInventoryQuery(session);
        var commandRepo = _runtime.Repositories.CreateInventoryCommand(session);
        return new InventoryView(session.SessionId, queryRepo, commandRepo);
    }

    public UserControl CreateMaterialsView(SessionContext session)
    {
        var queryRepo   = _runtime.Repositories.CreateSkuQuery(session);
        var commandRepo = _runtime.Repositories.CreateSkuCommand(session);
        return new MaterialsView(queryRepo, commandRepo, _runtime.ConnectionFactory);
    }

    public UserControl CreateSkuAuditView(SessionContext session)
    {
        var repo = _runtime.Repositories.CreateAuditQuery(session);
        return new SkuAuditView(repo);
    }

    public UserControl CreateLocationAuditView(SessionContext session)
    {
        var repo = _runtime.Repositories.CreateAuditQuery(session);
        return new LocationAuditView(repo);
    }

    public UserControl CreateOutstandingOrdersView(SessionContext session)
    {
        var queryRepo   = _runtime.Repositories.CreateOutboundQuery(session);
        var commandRepo = _runtime.Repositories.CreateOutboundCommand(session);
        var skuRepo     = _runtime.Repositories.CreateSkuQuery(session);
        var partyRepo   = _runtime.Repositories.CreatePartyQuery(session);
        return new PeasyWare.Desktop.Views.Outbound.OutstandingOrdersView(queryRepo, commandRepo, skuRepo, partyRepo);
    }

    public UserControl CreateInboundView(SessionContext session)
    {
        var queryRepo   = _runtime.Repositories.CreateInboundQuery(session);
        var commandRepo = _runtime.Repositories.CreateInboundCommand(session);
        var skuRepo     = _runtime.Repositories.CreateSkuQuery(session);
        var partyRepo   = _runtime.Repositories.CreatePartyQuery(session);
        return new InboundView(queryRepo, commandRepo, skuRepo, partyRepo);
    }

    public UserControl CreatePartiesView(SessionContext session, string? roleFilter = null)
    {
        var queryRepo   = _runtime.Repositories.CreatePartyQuery(session);
        var commandRepo = _runtime.Repositories.CreatePartyCommand(session);
        return new PartiesView(queryRepo, commandRepo, roleFilter);
    }

    public UserControl CreateMovementsView(SessionContext session)
    {
        var queryRepo = _runtime.Repositories.CreateMovementQuery(session);
        return new MovementsView(queryRepo);
    }

    public UserControl CreateEventLogView(SessionContext session, string? actionFilter = null)
    {
        var queryRepo = _runtime.Repositories.CreateEventLogQuery(session);
        var view      = new PeasyWare.Desktop.Views.Logs.EventLogView(queryRepo);
        if (actionFilter is not null)
            view.SetActionFilter(actionFilter);
        return view;
    }

    public UserControl CreateUserActivityView(SessionContext session)
    {
        var queryRepo = _runtime.Repositories.CreateEventLogQuery(session);
        return new PeasyWare.Desktop.Views.Logs.UserActivityView(queryRepo);
    }

    public UserControl CreateLocationsView(SessionContext session)
    {
        var queryRepo     = _runtime.Repositories.CreateLocationQuery(session);
        var commandRepo   = _runtime.Repositories.CreateLocationCommand(session);
        var inventoryRepo = _runtime.Repositories.CreateInventoryQuery(session);
        return new PeasyWare.Desktop.Views.Locations.LocationsView(queryRepo, commandRepo, inventoryRepo);
    }

    public UserControl CreateZonesView(SessionContext session)
    {
        var repo         = _runtime.Repositories.CreateZoneRepository(session);
        var locQuery     = _runtime.Repositories.CreateLocationQuery(session);
        var locCommand   = _runtime.Repositories.CreateLocationCommand(session);
        return new PeasyWare.Desktop.Views.Locations.ZonesView(repo, locQuery, locCommand);
    }

    public UserControl CreateSectionsView(SessionContext session)
    {
        var repo         = _runtime.Repositories.CreateSectionRepository(session);
        var locQuery     = _runtime.Repositories.CreateLocationQuery(session);
        var locCommand   = _runtime.Repositories.CreateLocationCommand(session);
        return new PeasyWare.Desktop.Views.Locations.SectionsView(repo, locQuery, locCommand);
    }

    public UserControl CreateStorageTypesView(SessionContext session)
    {
        var repo = _runtime.Repositories.CreateStorageTypeRepository(session);
        return new PeasyWare.Desktop.Views.Locations.StorageTypesView(repo);
    }

    public UserControl CreateShipmentsView(SessionContext session)
    {
        var queryRepo    = _runtime.Repositories.CreateOutboundQuery(session);
        var commandRepo  = _runtime.Repositories.CreateOutboundCommand(session);
        var manifestRepo = _runtime.Repositories.CreateShipmentManifest(session);
        var settingsRepo = _runtime.SettingsQueryRepository;
        var partyRepo    = _runtime.Repositories.CreatePartyQuery(session);
        return new ShipmentsView(queryRepo, commandRepo, manifestRepo, settingsRepo, partyRepo);
    }

    public UserControl CreateTasksView(SessionContext session)
    {
        return new TasksView(_runtime, session);
    }

}