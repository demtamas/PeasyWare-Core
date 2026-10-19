using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Flows;
using PeasyWare.Desktop.Forms;
using PeasyWare.Infrastructure.Bootstrap;
using PeasyWare.Infrastructure.Repositories;
using PeasyWare.Infrastructure.Settings;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Windows.Forms;

ApplicationConfiguration.Initialize(); // Sets STA, DPI mode, default font

AppRuntime runtime;
try
{
    runtime = AppStartup.Initialize();
}
catch (Exception ex)
{
    MessageBox.Show(
        ex.Message,
        "Startup failure",
        MessageBoxButtons.OK,
        MessageBoxIcon.Error);
    return;
}

var loginFlow = new LoginFlow(
    runtime.AuthService,
    runtime.UserSecurityRepository,
    runtime.Settings.DefaultUiMode);

var viewFactory = new ViewFactory(runtime);

try
{
    while (true)
    {
        // Between a logout and the next successful login nobody is signed in. Without
        // this the logger keeps the previous user's session, and every login attempt
        // (including failed ones by someone else) is logged under that user's identity.
        runtime.Logger.ClearSession();

        using var loginForm =
            new LoginForm(loginFlow, diagnosticsEnabled: false);

        if (loginForm.ShowDialog() != DialogResult.OK ||
            loginForm.SessionId is null ||
            loginForm.UserId is null)
        {
            break;
        }

        var session = new SessionContext(
            sessionId: loginForm.SessionId.Value,
            userId: loginForm.UserId.Value,
            username: loginForm.Username,
            displayName: loginForm.DisplayName,
            sourceApp: "PeasyWare.Desktop",
            sourceClient: Environment.MachineName,
            sourceIp: IpResolver.GetLocalIPv4(),
            correlationId: Guid.NewGuid(),
            osInfo: Environment.OSVersion.ToString(),
            roleName: loginForm.RoleName,
            uiMode: loginForm.UiMode,
            sessionTimeoutMinutes: loginForm.SessionTimeoutMinutes,
            permissions: loginForm.Permissions
        );

        // Same Session.Start entry the CLI writes after login. SetSession first, so the
        // entry itself carries the Session block; without it every Desktop session had
        // a Session.Logout in the trace with no matching start.
        runtime.Logger.SetSession(session);
        runtime.Logger.Info("Session.Start", new
        {
            session.UserId, session.Username, session.RoleName,
            UiMode = session.UiMode.ToString(), session.SourceApp, session.SourceClient
        });

        using var mainForm = new MainForm(
            session,
            runtime,
            viewFactory
        );

        var result = mainForm.ShowDialog();

        if (result == DialogResult.Abort)
            continue;

        break;
    }
}
finally
{
    AppStartup.Shutdown();
}