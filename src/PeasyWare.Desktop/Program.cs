using PeasyWare.Application.Contexts;
using PeasyWare.Application.Flows;
using PeasyWare.Desktop.Forms;
using PeasyWare.Infrastructure.Bootstrap;
using PeasyWare.Infrastructure.Repositories;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Windows.Forms;

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
    runtime.UserSecurityRepository);

// Create the UI view factory in the Desktop layer
var viewFactory = new ViewFactory(runtime);

try
{
    while (true)
    {
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
            correlationId: null,
            osInfo: Environment.OSVersion.ToString(),
            sessionTimeoutMinutes: loginForm.SessionTimeoutMinutes
        );

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