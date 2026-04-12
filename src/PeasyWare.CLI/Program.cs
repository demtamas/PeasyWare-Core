using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Flows;
using PeasyWare.Application.Interfaces;
using PeasyWare.CLI.Flows;
using PeasyWare.CLI.Networking;
using PeasyWare.Application.Dto;
using PeasyWare.CLI.UI;
using PeasyWare.Domain;
using PeasyWare.Infrastructure.Bootstrap;

var argsList = args.Select(a => a.ToLowerInvariant()).ToList();
var diagnosticsEnabled = argsList.Contains("--diag");

// --------------------------------------------------
// Startup
// --------------------------------------------------

AppRuntime runtime;

try
{
    runtime = AppStartup.Initialize();
}
catch (Exception ex)
{
    Console.WriteLine("FATAL: Startup failed.");
    Console.WriteLine(ex.Message);
    return;
}

// Login flow
var loginFlow = new LoginFlow(
    runtime.AuthService,
    runtime.UserSecurityRepository);

// --------------------------------------------------
// LOGIN LOOP
// --------------------------------------------------

Guid? sessionId = null;
int? userId = null;
string? username = null;
string? password = null;
string? displayName = null;
int sessionTimeoutMinutes = 480;

while (true)
{
    try
    {
        HeaderRenderer.Render(
            runtime.Settings,
            diagnosticsEnabled,
            sessionId: null);

        Console.WriteLine("Please log in to continue.\n");

        Console.Write("Username: ");
        username = Console.ReadLine();

        Console.Write("Password: ");
        password = ReadMaskedPassword();

        if (string.IsNullOrWhiteSpace(username) ||
            string.IsNullOrWhiteSpace(password))
        {
            Console.WriteLine("Username and password are required.");
            Console.ReadKey(true);
            continue;
        }

        var context = new LoginContext
        {
            ClientApp = "PeasyWare.CLI",
            ClientInfo = Environment.MachineName,
            OsInfo = Environment.OSVersion.ToString(),
            IpAddress = IpResolver.GetLocalIPv4() ?? "UNKNOWN",
            ForceLogin = false
        };

        var result = loginFlow.Run(
            username,
            password,
            context,
            diagnosticsEnabled);

        switch (result.Outcome)
        {
            case LoginOutcome.Success:

                sessionId = result.SessionId!.Value;
                userId = result.UserId!.Value;
                displayName = result.DisplayName;
                sessionTimeoutMinutes = result.SessionTimeoutMinutes;

                goto LoginSucceeded;

            case LoginOutcome.PasswordChangeRequired:

                Console.WriteLine(result.Message);
                Console.WriteLine();

                bool changed = false;

                for (int i = 0; i < 3; i++)
                {
                    var newPassword = ReadConfirmedPassword();
                    var change = loginFlow.ChangePassword(username, newPassword);

                    if (change.Success)
                    {
                        password = newPassword;
                        changed = true;
                        break;
                    }

                    Console.WriteLine(change.FriendlyMessage);
                }

                if (!changed)
                    return;

                continue;

            case LoginOutcome.AlreadyLoggedIn:

                Console.WriteLine(result.Message);
                Console.Write("Terminate the other session and continue? (y/N): ");

                var answer = Console.ReadLine();

                if (!string.Equals(answer, "y", StringComparison.OrdinalIgnoreCase))
                    return;

                var forcedContext = new LoginContext
                {
                    ClientApp = context.ClientApp,
                    ClientInfo = context.ClientInfo,
                    OsInfo = context.OsInfo,
                    IpAddress = context.IpAddress,
                    ForceLogin = true
                };

                var retry = loginFlow.Run(
                    username,
                    password,
                    forcedContext,
                    diagnosticsEnabled);

                if (retry.Outcome != LoginOutcome.Success)
                {
                    Console.WriteLine(retry.Message);
                    Console.ReadKey(true);
                    continue;
                }

                sessionId = retry.SessionId!.Value;
                userId = retry.UserId!.Value;
                displayName = retry.DisplayName;
                sessionTimeoutMinutes = retry.SessionTimeoutMinutes;

                goto LoginSucceeded;

            default:

                Console.WriteLine(result.Message ?? "Login failed.");
                Console.ReadKey(true);
                continue;
        }
    }
    catch (Exception ex)
    {
        runtime.Logger.Error("CLI.Login.Exception", ex);
        Console.WriteLine($"Login failed: {ex.Message}");
        Console.ReadKey(true);
    }
}

LoginSucceeded:

// --------------------------------------------------
// SESSION CONTEXT
// --------------------------------------------------

var session = new SessionContext(
    sessionId: sessionId!.Value,
    userId: userId!.Value,
    username: username!,
    displayName: displayName ?? username!,
    sourceApp: "PeasyWare.CLI",
    sourceClient: Environment.MachineName,
    sourceIp: IpResolver.GetLocalIPv4(),
    correlationId: Guid.NewGuid(),
    osInfo: Environment.OSVersion.ToString(),
    sessionTimeoutMinutes: sessionTimeoutMinutes
);

// 🔥 IMPORTANT: bind logger to session
runtime.Logger.SetSession(session);

// --------------------------------------------------
// Header (post-login)
// --------------------------------------------------

HeaderRenderer.Render(
    runtime.Settings,
    diagnosticsEnabled,
    session.SessionId);

Console.WriteLine("Login successful. Welcome back!\n");

// --------------------------------------------------
// MAIN LOOP
// --------------------------------------------------

try
{
    while (true)
    {
        var input = MenuRenderer.ShowMainMenu();

        switch (input)
        {
            case "1":
                RunInbound(runtime, session);
                break;

            case "7":
                {
                    var sessionCommand =
                        runtime.Repositories.CreateSessionCommand(session);

                    var logout = sessionCommand.LogoutSession(
                        session.SessionId,
                        sourceApp: "PeasyWare.CLI",
                        sourceClient: Environment.MachineName,
                        sourceIp: IpResolver.GetLocalIPv4());

                    Console.WriteLine(logout.FriendlyMessage);
                    return;
                }

            case "0":
                Console.WriteLine("Exiting application.");
                return;

            default:
                Console.WriteLine("Invalid option.");
                break;
        }
    }
}
catch (Exception ex)
{
    runtime.Logger.Error("CLI.Runtime.Exception", ex);
    Console.WriteLine($"Runtime error: {ex.Message}");
}
finally
{
    AppStartup.Shutdown();
}

// --------------------------------------------------
// INBOUND MENU
// --------------------------------------------------

static void RunInbound(AppRuntime runtime, SessionContext session)
{
    var inboundQuery = runtime.Repositories.CreateInboundQuery(session);
    var inboundCommand = runtime.Repositories.CreateInboundCommand(session);

    while (true)
    {
        var inboundInput = MenuRenderer.ShowInboundMenu();

        switch (inboundInput)
        {
            case "1":
                {
                    var activatable = inboundQuery.GetActivatableInbounds();

                    var refInput =
                        ActivateInboundScreen.PromptInboundRef(activatable);

                    if (string.IsNullOrWhiteSpace(refInput))
                        return;

                    var result =
                        inboundCommand.ActivateInboundByRef(refInput);

                    Console.WriteLine();
                    Console.WriteLine(result.FriendlyMessage);

                    Console.ReadKey(true);
                    break;
                }

            case "2":
                {
                    var flow = new ReceiveInboundFlow(runtime, session);
                    flow.Run();
                    break;
                }

            case "3":
                {
                    var flow = new PutawayFromInboundFlow(runtime, session);
                    flow.RunAsync().Wait();
                    break;
                }

            case "0":
                return;

            default:
                Console.WriteLine("Invalid option.");
                break;
        }
    }
}

// --------------------------------------------------
// Helpers
// --------------------------------------------------

static string ReadConfirmedPassword(int maxTries = 3)
{
    for (int attempt = 1; attempt <= maxTries; attempt++)
    {
        Console.Write("Enter new password: ");
        var p1 = ReadMaskedPassword();

        Console.Write("Confirm new password: ");
        var p2 = ReadMaskedPassword();

        if (!string.IsNullOrWhiteSpace(p1) && p1 == p2)
            return p1;

        Console.WriteLine("Passwords do not match.");
    }

    throw new InvalidOperationException("Password change failed.");
}

static string ReadMaskedPassword()
{
    var buffer = new List<char>();

    while (true)
    {
        var key = Console.ReadKey(intercept: true);

        if (key.Key == ConsoleKey.Enter)
        {
            Console.WriteLine();
            break;
        }

        if (key.Key == ConsoleKey.Backspace && buffer.Count > 0)
        {
            buffer.RemoveAt(buffer.Count - 1);
            Console.Write("\b \b");
            continue;
        }

        if (!char.IsControl(key.KeyChar))
        {
            buffer.Add(key.KeyChar);
            Console.Write("*");
        }
    }

    return new string(buffer.ToArray());
}