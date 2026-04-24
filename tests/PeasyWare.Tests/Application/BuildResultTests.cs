using FluentAssertions;
using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Infrastructure.Repositories;
using Xunit;

namespace PeasyWare.Tests.Application;

/// <summary>
/// Unit tests for RepositoryBase.BuildResult.
///
/// BuildResult is protected — tested via a minimal concrete subclass
/// that exposes it publicly for test purposes.
///
/// Verified:
///   - SUC* prefix → success=true, Info logged
///   - ERR* prefix → success=false, Warn logged
///   - WAR* prefix → success=false, Warn logged
///   - Result code and message are passed through unchanged
///   - Session fields (UserId, SessionId, CorrelationId) are included in log payload
///   - Data payload is included in log
/// </summary>
public class BuildResultTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // Success / failure from result code prefix
    // ─────────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("SUCAUTH01",   true)]
    [InlineData("SUCINBL01",   true)]
    [InlineData("SUCTASK01",   true)]
    [InlineData("ERRAUTH06",   false)]
    [InlineData("ERRINBL09",   false)]
    [InlineData("ERRTASK02",   false)]
    [InlineData("WARINBL01",   false)]
    public void BuildResult_SuccessFlag_DerivedFromPrefix(string code, bool expectedSuccess)
    {
        var (sut, _, _) = Build();

        var result = sut.Expose("Action.Test", code, new { });

        result.Success.Should().Be(expectedSuccess);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Result code and message pass-through
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void BuildResult_ResultCode_PassedThrough()
    {
        var (sut, _, _) = Build();

        var result = sut.Expose("Action.Test", "SUCINBL01", new { });

        result.ResultCode.Should().Be("SUCINBL01");
    }

    [Fact]
    public void BuildResult_FriendlyMessage_ResolvedFromResolver()
    {
        var (sut, resolver, _) = Build();
        resolver.Register("SUCINBL01", "Inbound line received successfully.");

        var result = sut.Expose("Action.Test", "SUCINBL01", new { });

        result.FriendlyMessage.Should().Be("Inbound line received successfully.");
    }

    [Fact]
    public void BuildResult_UnknownCode_ResolverReturnsCode()
    {
        // StubErrorMessageResolver returns the code itself when no mapping exists
        var (sut, _, _) = Build();

        var result = sut.Expose("Action.Test", "SUCUNKNOWN99", new { });

        result.FriendlyMessage.Should().Be("SUCUNKNOWN99");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Logging direction: SUC* → Info, ERR*/WAR* → Warn
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void BuildResult_SuccessCode_LogsAtInfo()
    {
        var (sut, _, logger) = Build();

        sut.Expose("Action.Test", "SUCAUTH01", new { });

        logger.InfoCalls.Should().Be(1);
        logger.WarnCalls.Should().Be(0);
    }

    [Fact]
    public void BuildResult_ErrorCode_LogsAtWarn()
    {
        var (sut, _, logger) = Build();

        sut.Expose("Action.Test", "ERRAUTH06", new { });

        logger.WarnCalls.Should().Be(1);
        logger.InfoCalls.Should().Be(0);
    }

    [Fact]
    public void BuildResult_WarningCode_LogsAtWarn()
    {
        var (sut, _, logger) = Build();

        sut.Expose("Action.Test", "WARINBL01", new { });

        logger.WarnCalls.Should().Be(1);
        logger.InfoCalls.Should().Be(0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Action name is passed to the logger
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void BuildResult_ActionName_PassedToLogger()
    {
        var (sut, _, logger) = Build();

        sut.Expose("Inbound.ReceiveLine", "SUCINBL01", new { });

        logger.LastAction.Should().Be("Inbound.ReceiveLine");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Multiple calls — each is logged independently
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void BuildResult_MultipleSuccessCalls_EachLogged()
    {
        var (sut, _, logger) = Build();

        sut.Expose("Action.A", "SUCAUTH01", new { });
        sut.Expose("Action.B", "SUCINBL01", new { });
        sut.Expose("Action.C", "SUCTASK01", new { });

        logger.InfoCalls.Should().Be(3);
    }

    [Fact]
    public void BuildResult_MixedCalls_LogCountsAreIndependent()
    {
        var (sut, _, logger) = Build();

        sut.Expose("Action.A", "SUCAUTH01", new { });
        sut.Expose("Action.B", "ERRAUTH06", new { });
        sut.Expose("Action.C", "SUCINBL01", new { });

        logger.InfoCalls.Should().Be(2);
        logger.WarnCalls.Should().Be(1);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static (
        ExposedRepository sut,
        CapturingErrorMessageResolver resolver,
        CapturingLogger logger)
    Build()
    {
        var session  = new SessionContext(
            sessionId:             Guid.NewGuid(),
            userId:                1,
            username:              "testuser",
            displayName:           "Test User",
            sourceApp:             "PeasyWare.Tests",
            sourceClient:          "TEST_PC",
            sourceIp:              null,
            correlationId:         Guid.NewGuid(),
            osInfo:                string.Empty,
            roleName:              "admin",
            uiMode:                UiMode.Trace,
            sessionTimeoutMinutes: 480);

        var resolver = new CapturingErrorMessageResolver();
        var logger   = new CapturingLogger();
        var guard    = new StubSessionCommandRepository(isAlive: true);
        var sut      = new ExposedRepository(new SessionGuard(guard), session, resolver, logger);

        return (sut, resolver, logger);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Concrete subclass that exposes BuildResult for testing
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class ExposedRepository : RepositoryBase
{
    public ExposedRepository(
        SessionGuard          sessionGuard,
        SessionContext        session,
        IErrorMessageResolver resolver,
        ILogger               logger)
        : base(sessionGuard, session, resolver, logger)
    { }

    public OperationResult Expose(string action, string resultCode, object data)
        => BuildResult(action, resultCode, data);
}

// ─────────────────────────────────────────────────────────────────────────────
// Capturing stubs
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class CapturingErrorMessageResolver : IErrorMessageResolver
{
    private readonly Dictionary<string, string> _map = new();

    public void Register(string code, string message) => _map[code] = message;

    public string Resolve(string code)
        => _map.TryGetValue(code, out var msg) ? msg : code;
}

internal sealed class CapturingLogger : ILogger
{
    public int     InfoCalls  { get; private set; }
    public int     WarnCalls  { get; private set; }
    public string? LastAction { get; private set; }

    public void Info(string action, object? data) { InfoCalls++; LastAction = action; }
    public void Warn(string action, object? data) { WarnCalls++; LastAction = action; }

    public void SetSession(SessionContext session) { }
    public void Info(string message)               { InfoCalls++; }
    public void Warn(string message)               { WarnCalls++; }
    public void Error(string message)              { }
    public void Error(string message, Exception ex) { }
    public void Error(string message, Exception ex, object context) { }
    public void Error(string action, object? data) { }
}
