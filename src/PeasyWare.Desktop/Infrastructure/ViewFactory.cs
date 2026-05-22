using PeasyWare.Application.Contexts;
using PeasyWare.Desktop.Views.Inbound;
using PeasyWare.Desktop.Views.Inventory;
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

    public UserControl CreateOutstandingOrdersView(SessionContext session)
    {
        var queryRepo = _runtime.Repositories.CreateOutboundQuery(session);
        var commandRepo = _runtime.Repositories.CreateOutboundCommand(session);
        return new PeasyWare.Desktop.Views.Outbound.OutstandingOrdersView(queryRepo, commandRepo);
    }

    public UserControl CreateInboundView(SessionContext session)
    {
        var queryRepo = _runtime.Repositories.CreateInboundQuery(session);
        return new InboundView(queryRepo);
    }

    public UserControl CreateShipmentsView(SessionContext session)
    {
        var queryRepo   = _runtime.Repositories.CreateOutboundQuery(session);
        var commandRepo = _runtime.Repositories.CreateOutboundCommand(session);
        return new ShipmentsView(queryRepo, commandRepo);
    }

    public UserControl CreateTasksView(SessionContext session)
    {
        return new TasksView(_runtime, session);
    }

}