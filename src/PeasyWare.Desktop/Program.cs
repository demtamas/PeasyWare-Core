using PeasyWare.Application.Contexts;
using PeasyWare.Application.Flows;
using PeasyWare.Desktop.Forms;
using PeasyWare.Infrastructure.Bootstrap;
using PeasyWare.Infrastructure.Repositories;
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
            loginForm.SessionId.Value,
            loginForm.UserId.Value,
            loginForm.Username   // or DisplayName if you prefer
        );

        using var mainForm = new MainForm(
            session,
            runtime.ConnectionFactory,
            runtime.ErrorMessageResolver,
            runtime.SessionQueryRepository,
            new SqlSessionCommandRepository(
                runtime.ConnectionFactory,
                session.SessionId,
                session.UserId,
                runtime.ErrorMessageResolver),
            runtime.SessionDetailsRepository,
            runtime.UserQueryRepository,
            runtime.Logger
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
