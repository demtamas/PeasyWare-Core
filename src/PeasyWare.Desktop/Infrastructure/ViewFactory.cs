using PeasyWare.Application.Contexts;
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
}