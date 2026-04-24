using FluentAssertions;
using PeasyWare.Application;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using Xunit;

namespace PeasyWare.Tests.Application;

/// <summary>
/// Unit tests for SessionGuard.EnsureActive.
///
/// SessionGuard calls TouchSession on the repo.
/// If IsAlive = false → throws SessionExpiredException.
/// If IsAlive = true  → returns normally.
/// </summary>
public class SessionGuardTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // Happy path
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void EnsureActive_AliveSession_DoesNotThrow()
    {
        var repo  = new StubSessionCommandRepository(isAlive: true);
        var guard = new SessionGuard(repo);

        var act = () => guard.EnsureActive(Guid.NewGuid());

        act.Should().NotThrow();
    }

    [Fact]
    public void EnsureActive_AliveSession_CallsTouchSession()
    {
        var repo  = new StubSessionCommandRepository(isAlive: true);
        var guard = new SessionGuard(repo);

        guard.EnsureActive(Guid.NewGuid());

        repo.TouchCalled.Should().BeTrue();
    }

    [Fact]
    public void EnsureActive_AliveSession_PassesCorrectSessionId()
    {
        var repo      = new StubSessionCommandRepository(isAlive: true);
        var guard     = new SessionGuard(repo);
        var sessionId = Guid.NewGuid();

        guard.EnsureActive(sessionId);

        repo.LastSessionId.Should().Be(sessionId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Expired / dead session
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void EnsureActive_DeadSession_ThrowsSessionExpiredException()
    {
        var repo  = new StubSessionCommandRepository(isAlive: false);
        var guard = new SessionGuard(repo);

        var act = () => guard.EnsureActive(Guid.NewGuid());

        act.Should().Throw<SessionExpiredException>();
    }

    [Fact]
    public void EnsureActive_DeadSession_ExceptionMessageIsFromRepo()
    {
        var repo  = new StubSessionCommandRepository(isAlive: false, message: "Your session has expired.");
        var guard = new SessionGuard(repo);

        var act = () => guard.EnsureActive(Guid.NewGuid());

        act.Should().Throw<SessionExpiredException>()
           .WithMessage("Your session has expired.");
    }

    [Fact]
    public void EnsureActive_DeadSession_CustomMessage_PropagatesCorrectly()
    {
        var repo  = new StubSessionCommandRepository(isAlive: false, message: "Session terminated by administrator.");
        var guard = new SessionGuard(repo);

        var act = () => guard.EnsureActive(Guid.NewGuid());

        act.Should().Throw<SessionExpiredException>()
           .WithMessage("Session terminated by administrator.");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Multiple calls — each call goes through to the repo
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void EnsureActive_CalledMultipleTimes_TouchesRepoEachTime()
    {
        var repo  = new StubSessionCommandRepository(isAlive: true);
        var guard = new SessionGuard(repo);
        var id    = Guid.NewGuid();

        guard.EnsureActive(id);
        guard.EnsureActive(id);
        guard.EnsureActive(id);

        repo.TouchCount.Should().Be(3);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stub
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class StubSessionCommandRepository : ISessionCommandRepository
{
    private readonly bool   _isAlive;
    private readonly string _message;

    public bool   TouchCalled   { get; private set; }
    public int    TouchCount    { get; private set; }
    public Guid   LastSessionId { get; private set; }

    public StubSessionCommandRepository(bool isAlive, string message = "Session expired.")
    {
        _isAlive = isAlive;
        _message = message;
    }

    public SessionTouchResult TouchSession(
        Guid   sessionId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null)
    {
        TouchCalled   = true;
        TouchCount++;
        LastSessionId = sessionId;

        return new SessionTouchResult
        {
            IsAlive         = _isAlive,
            ResultCode      = _isAlive ? "SUCAUTH02" : "ERRAUTH06",
            FriendlyMessage = _message
        };
    }

    public OperationResult LogoutSession(
        Guid   sessionId,
        string sourceApp,
        string sourceClient,
        string? sourceIp = null)
        => OperationResult.Create(true, "SUCAUTH03", "Logged out.");
}
