using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Flows;
using PeasyWare.Application.Interfaces;
using PeasyWare.CLI.Flows;
using PeasyWare.CLI.Networking;
using PeasyWare.CLI.UI;
using PeasyWare.Domain;
using PeasyWare.Infrastructure.Bootstrap;
using PeasyWare.Infrastructure.Errors;
using PeasyWare.Infrastructure.Logging;
using PeasyWare.Infrastructure.Repositories;
using System;
using System.Collections.Generic;
using System.Linq;

// --------------------------------------------------
// Startup
// --------------------------------------------------

var argsList = args.Select(a => a.ToLowerInvariant()).ToList();
var diagnosticsEnabled = argsList.Contains("--diag");

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

// Login flow (pre-session)
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
            Console.WriteLine("Press any key to try again...");
            Console.ReadKey(true);
            continue;
        }

        CorrelationContext.Set(Guid.NewGuid());

        var context = new LoginContext
        {
            ClientApp = "PeasyWare.CLI",
            ClientInfo = Environment.MachineName,
            OsInfo = Environment.OSVersion.ToString(),
            IpAddress = IpResolver.GetLocalIPv4(),
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

                continue; // retry login with new password

            case LoginOutcome.AlreadyLoggedIn:
                Console.WriteLine(result.Message);
                Console.Write("Terminate the other session and continue? (y/N): ");

                var answer = Console.ReadLine();
                if (!string.Equals(answer, "y", StringComparison.OrdinalIgnoreCase))
                    return;

                var forcedContext = new LoginContext
                {
                    ClientApp = "PeasyWare.CLI",
                    ClientInfo = Environment.MachineName,
                    OsInfo = Environment.OSVersion.ToString(),
                    IpAddress = IpResolver.GetLocalIPv4(),
                    ForceLogin = true
                };

                var retry = loginFlow.Run(
                    username,
                    password,
                    forcedContext,
                    diagnosticsEnabled);

                if (!retry.Success)
                {
                    Console.WriteLine(retry.Message);
                    Console.WriteLine("Press any key to try again...");
                    Console.ReadKey(true);
                    continue;
                }

                sessionId = retry.SessionId!.Value;
                userId = retry.UserId!.Value;
                goto LoginSucceeded;

            default:
                Console.WriteLine(result.Message ?? "Login failed.");
                Console.WriteLine("Press any key to try again...");
                Console.ReadKey(true);
                continue;
        }
    }
    catch (Exception ex)
    {
        runtime.Logger.Error("Unhandled exception during login", ex);
        Console.WriteLine($"Login failed: {ex.Message}");
        Console.WriteLine("Press any key to try again...");
        Console.ReadKey(true);
    }
}

LoginSucceeded:

// --------------------------------------------------
// SESSION CONTEXT (CRITICAL)
// --------------------------------------------------

var session = new SessionContext(
    sessionId!.Value,
    userId!.Value,
    username!);

// Session-scoped command repo
var sessionCommandRepo =
    new SqlSessionCommandRepository(
        runtime.ConnectionFactory,
        session.SessionId,
        session.UserId,
        runtime.ErrorMessageResolver,
        runtime.Logger);

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
        var touch =
            sessionCommandRepo.TouchSession(session.SessionId);

        if (!touch.IsAlive)
        {
            Console.WriteLine(touch.FriendlyMessage);
            Console.WriteLine("Session ended.");
            return;
        }

        var input = MenuRenderer.ShowMainMenu();

        switch (input)
        {
            case "1":
                {
                    while (true)
                    {
                        var inboundInput = MenuRenderer.ShowInboundMenu();

                        switch (inboundInput)
                        {
                            case "1":
                                RunActivateInbound(runtime, session);
                                break;

                            case "2":
                                {
                                    var flow = new ReceiveInboundFlow(runtime, session);
                                    flow.Run();
                                    break;
                                }

                            case "3":
                                {
                                    var flow = new PutawayFromInboundFlow(runtime, session);
                                    await flow.RunAsync();
                                    break;
                                }

                            case "0":
                                goto ExitInbound;

                            default:
                                Console.WriteLine("Invalid option.");
                                break;
                        }
                    }

                ExitInbound:
                    break;
                }

            case "7":
                {
                    var logout =
                        sessionCommandRepo.LogoutSession(
                            session.SessionId,
                            sourceApp: "PeasyWare.CLI",
                            sourceClient: Environment.MachineName,
                            sourceIp: IpResolver.GetLocalIPv4());

                    Console.WriteLine(logout.FriendlyMessage);
                    return;
                }

            case "3":
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
    runtime.Logger.Error("Unhandled CLI runtime error", ex);
    Console.WriteLine($"Runtime error: {ex.Message}");
}
finally
{
    AppStartup.Shutdown();
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

        if (string.IsNullOrWhiteSpace(p1) || string.IsNullOrWhiteSpace(p2))
            continue;

        if (p1 == p2)
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

        if (key.Key == ConsoleKey.Backspace)
        {
            if (buffer.Count > 0)
            {
                buffer.RemoveAt(buffer.Count - 1);
                Console.Write("\b \b");
            }
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

static void RunActivateInbound(
    AppRuntime runtime,
    SessionContext session)
{
    var queryRepo = new SqlInboundQueryRepository(
        runtime.ConnectionFactory,
        session.SessionId,
        session.UserId,
        runtime.ErrorMessageResolver);

    var commandRepo = new SqlInboundCommandRepository(
    runtime.ConnectionFactory,
    session.SessionId,
    session.UserId,
    runtime.ErrorMessageResolver,
    runtime.Logger);

    var activatable = queryRepo.GetActivatableInbounds();

    var refInput =
        ActivateInboundScreen.PromptInboundRef(activatable);

    if (string.IsNullOrWhiteSpace(refInput))
        return;

    var result =
        commandRepo.ActivateInboundByRef(refInput);

    Console.WriteLine();
    Console.WriteLine(result.FriendlyMessage);

    if (result.Success)
        Console.WriteLine("Inbound activated successfully.");

    Console.WriteLine("Press any key to continue...");
    Console.ReadKey(true);
}

