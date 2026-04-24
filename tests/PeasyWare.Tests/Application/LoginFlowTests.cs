using FluentAssertions;
using PeasyWare.Application;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Flows;
using PeasyWare.Application.Interfaces;
using Xunit;

namespace PeasyWare.Tests.Application;

/// <summary>
/// Unit tests for LoginFlow.ResolveUiMode.
///
/// The system default acts as a global ceiling — no role can exceed it.
///
/// Role maximums:
///   admin   → Trace    (3)
///   manager → Standard (2)
///   *       → Minimal  (1)
///
/// UiMode enum values (ascending):
///   Minimal  = 1
///   Standard = 2
///   Trace    = 3
/// </summary>
public class LoginFlowTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // Default = Trace — roles get their full allocation
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ResolveUiMode_Admin_DefaultTrace_ReturnsTrace()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: "admin");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Trace);
    }

    [Fact]
    public void ResolveUiMode_Manager_DefaultTrace_ReturnsStandard()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: "manager");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Standard);
    }

    [Fact]
    public void ResolveUiMode_Operator_DefaultTrace_ReturnsMinimal()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: "operator");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Default = Standard — admin is capped at Standard
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ResolveUiMode_Admin_DefaultStandard_CappedAtStandard()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Standard, resultRole: "admin");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Standard);
    }

    [Fact]
    public void ResolveUiMode_Manager_DefaultStandard_ReturnsStandard()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Standard, resultRole: "manager");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Standard);
    }

    [Fact]
    public void ResolveUiMode_Operator_DefaultStandard_ReturnsMinimal()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Standard, resultRole: "operator");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Default = Minimal — everyone is capped at Minimal
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ResolveUiMode_Admin_DefaultMinimal_CappedAtMinimal()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Minimal, resultRole: "admin");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    [Fact]
    public void ResolveUiMode_Manager_DefaultMinimal_CappedAtMinimal()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Minimal, resultRole: "manager");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    [Fact]
    public void ResolveUiMode_Operator_DefaultMinimal_ReturnsMinimal()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Minimal, resultRole: "operator");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Role casing — role matching must be case-insensitive
    // ─────────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("ADMIN")]
    [InlineData("Admin")]
    [InlineData("aDmIn")]
    public void ResolveUiMode_AdminRoleCasing_DefaultTrace_ReturnsTrace(string role)
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: role);

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Trace);
    }

    [Theory]
    [InlineData("MANAGER")]
    [InlineData("Manager")]
    [InlineData("mAnAgEr")]
    public void ResolveUiMode_ManagerRoleCasing_DefaultTrace_ReturnsStandard(string role)
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: role);

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Standard);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Unknown / null role — falls back to Minimal
    // ─────────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("supervisor")]
    [InlineData("superuser")]
    [InlineData("")]
    public void ResolveUiMode_UnknownRole_DefaultTrace_ReturnsMinimal(string role)
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: role);

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    [Fact]
    public void ResolveUiMode_NullRole_DefaultTrace_ReturnsMinimal()
    {
        var flow = BuildFlow(defaultUiMode: UiMode.Trace, resultRole: null);

        var result = flow.Run("u", "p", MakeContext(), false);

        result.UiMode.Should().Be(UiMode.Minimal);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Outcome routing — non-UiMode paths
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Run_PasswordChangeRequired_ReturnsCorrectOutcome()
    {
        var flow = BuildFlow(resultCode: "ERRAUTH09");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.Outcome.Should().Be(LoginOutcome.PasswordChangeRequired);
    }

    [Fact]
    public void Run_AlreadyLoggedIn_ReturnsCorrectOutcome()
    {
        var flow = BuildFlow(resultCode: "ERRAUTH05");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.Outcome.Should().Be(LoginOutcome.AlreadyLoggedIn);
    }

    [Fact]
    public void Run_UnknownErrorCode_ReturnsFailed()
    {
        var flow = BuildFlow(resultCode: "ERRAUTH99");

        var result = flow.Run("u", "p", MakeContext(), false);

        result.Outcome.Should().Be(LoginOutcome.Failed);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static LoginFlow BuildFlow(
        UiMode defaultUiMode  = UiMode.Trace,
        string? resultRole    = "admin",
        string resultCode     = "SUCAUTH01")
    {
        var loginRepo = new StubLoginRepository(resultCode, resultRole);
        var authService = new AuthService(loginRepo, new StubUserSecurityRepository(), new CapturingLogger());
        return new LoginFlow(authService, new StubUserSecurityRepository(), defaultUiMode);
    }

    private static LoginContext MakeContext() => new()
    {
        ClientApp     = "PeasyWare.Tests",
        ClientInfo    = "TEST_MACHINE",
        OsInfo        = "TestOS",
        IpAddress     = "127.0.0.1",
        CorrelationId = Guid.NewGuid()
    };
}

// ─────────────────────────────────────────────────────────────────────────────
// Stubs
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class StubLoginRepository : ILoginRepository
{
    private readonly string  _resultCode;
    private readonly string? _roleName;

    public StubLoginRepository(string resultCode = "SUCAUTH01", string? roleName = "admin")
    {
        _resultCode = resultCode;
        _roleName   = roleName;
    }

    public LoginResult Login(string username, string? password, LoginContext context)
    {
        var success = _resultCode.StartsWith("SUC");
        return new LoginResult
        {
            Success        = success,
            ResultCode     = _resultCode,
            FriendlyMessage = _resultCode,
            SessionId      = success ? Guid.NewGuid() : null,
            UserId         = success ? 1 : null,
            DisplayName    = username,
            RoleName       = _roleName,
            SessionTimeoutMinutes = 480
        };
    }
}

internal sealed class StubUserSecurityRepository : IUserSecurityRepository
{
    public OperationResult ChangePassword(string username, string newPassword)
        => OperationResult.Create(true, "SUCAUTH10", "Password changed.");
}
