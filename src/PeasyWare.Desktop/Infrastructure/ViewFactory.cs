using PeasyWare.Application.Contexts;
using PeasyWare.Desktop.Views.Inventory;
using PeasyWare.Desktop.Views.Materials;
using PeasyWare.Desktop.Views.Sessions;
using PeasyWare.Desktop.Views.Settings;
using PeasyWare.Desktop.Views.Users;
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
        var queryRepo = _runtime.Repositories.CreateInventoryQuery(session);
        return new InventoryView(session.SessionId, queryRepo);
    }

    public UserControl CreateMaterialsView(SessionContext session)
    {
        var queryRepo   = _runtime.Repositories.CreateSkuQuery(session);
        var commandRepo = _runtime.Repositories.CreateSkuCommand(session);
        return new MaterialsView(queryRepo, commandRepo, _runtime.ConnectionFactory);
    }
}