using FluentAssertions;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Flows;
using PeasyWare.Application.Interfaces;
using Xunit;

namespace PeasyWare.Tests.Application;

/// <summary>
/// A forced password change (ERRAUTH09) is part of a login attempt. Its log entries
/// must carry that attempt's correlation ID, otherwise the trace log shows the failed
/// login, then a change with no correlation at all, then a second login - three
/// unrelated-looking events for one operation. The logger fills its correlation column
/// from a CorrelationId property in the payload, so the contract tested here is:
/// the ID given to LoginFlow.ChangePassword reaches the repository and appears in
/// both AuthService log entries.
/// </summary>
public class PasswordChangeCorrelationTests
{
    [Fact]
    public void ChangePassword_PassesTheCorrelationIdDownToTheRepository()
    {
        var (flow, _, security) = Build();
        var correlationId = Guid.NewGuid();

        flow.ChangePassword("admin", "NewPassw0rd", correlationId);

        security.LastCorrelationId.Should().Be(correlationId);
    }

    [Fact]
    public void ChangePassword_LogsStartAndResult_OnTheLoginAttemptsCorrelationId()
    {
        var (flow, logger, _) = Build();
        var correlationId = Guid.NewGuid();

        flow.ChangePassword("admin", "NewPassw0rd", correlationId);

        var start  = logger.Entries.Single(e => e.Action == "AuthService.PasswordChange.Start");
        var result = logger.Entries.Single(e => e.Action == "AuthService.PasswordChange.Result");

        CorrelationOf(start.Payload).Should().Be(correlationId);
        CorrelationOf(result.Payload).Should().Be(correlationId);
    }

    [Fact]
    public void ChangePassword_WithoutACorrelationId_StillWorks_AndCarriesNone()
    {
        var (flow, logger, security) = Build();

        var result = flow.ChangePassword("admin", "NewPassw0rd");

        result.Success.Should().BeTrue();
        security.LastCorrelationId.Should().Be(Guid.Empty);

        // Guid.Empty is what the logger treats as "none" (the column stays NULL)
        logger.Entries
              .Select(e => CorrelationOf(e.Payload))
              .Should().OnlyContain(c => c == Guid.Empty);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static Guid? CorrelationOf(object? payload)
        => payload?.GetType().GetProperty("CorrelationId")?.GetValue(payload) as Guid?;

    private static (LoginFlow flow, RecordingLogger logger, RecordingSecurityRepository security) Build()
    {
        var logger   = new RecordingLogger();
        var security = new RecordingSecurityRepository();
        var auth     = new AuthService(new StubLoginRepository(), security, logger);
        var flow     = new LoginFlow(auth, security, UiMode.Trace);

        return (flow, logger, security);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stubs
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class RecordingSecurityRepository : IUserSecurityRepository
{
    public Guid? LastCorrelationId { get; private set; }

    public OperationResult ChangePassword(string username, string newPassword, Guid correlationId = default)
    {
        LastCorrelationId = correlationId;
        return OperationResult.Create(true, "SUCAUTH10", "Password changed.");
    }
}

/// <summary>Keeps every entry (CapturingLogger keeps only the last).</summary>
internal sealed class RecordingLogger : ILogger
{
    public List<(string Action, object? Payload)> Entries { get; } = new();

    public void SetSession(SessionContext session) { }
    public void Info(string action, object? data)  => Entries.Add((action, data));
    public void Warn(string action, object? data)  => Entries.Add((action, data));
    public void Error(string action, object? data) { }
    public void Error(string action, object? data, Exception ex) { }
}
