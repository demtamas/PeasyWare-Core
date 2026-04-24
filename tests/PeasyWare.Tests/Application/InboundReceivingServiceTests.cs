using FluentAssertions;
using PeasyWare.Application;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Services;
using Xunit;

namespace PeasyWare.Tests.Application;

/// <summary>
/// Unit tests for InboundReceivingService.
///
/// Uses hand-rolled stubs — no Moq dependency.
/// Tests verify that the service delegates correctly to its repositories
/// and passes the right parameters through.
/// </summary>
public class InboundReceivingServiceTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // ValidateSscc — delegates to query repo
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ValidateSscc_DelegatesToQueryRepo()
    {
        var stub    = new StubInboundQueryRepo();
        var service = new InboundReceivingService(stub, new StubInboundCommandRepo(), new StubErrorMessageResolver());

        service.ValidateSscc("SSCC001", "BAY01");

        stub.ValidateSsccCalled.Should().BeTrue();
        stub.LastExternalRef.Should().Be("SSCC001");
        stub.LastStagingBin.Should().Be("BAY01");
    }

    [Fact]
    public void ValidateSscc_ReturnsRepoResult()
    {
        var stub = new StubInboundQueryRepo
        {
            ValidateSsccResult = new SsccValidationDto { Success = true, FriendlyMessage = "OK", InboundRef = "INB001" }
        };

        var result = new InboundReceivingService(stub, new StubInboundCommandRepo(), new StubErrorMessageResolver())
            .ValidateSscc("SSCC001", "BAY01");

        result.Success.Should().BeTrue();
        result.InboundRef.Should().Be("INB001");
    }

    [Fact]
    public void ValidateSscc_WhenRepoReturnsFail_ReturnsFail()
    {
        var stub = new StubInboundQueryRepo
        {
            ValidateSsccResult = new SsccValidationDto { Success = false, FriendlyMessage = "SSCC not found." }
        };

        var result = new InboundReceivingService(stub, new StubInboundCommandRepo(), new StubErrorMessageResolver())
            .ValidateSscc("UNKNOWN", "BAY01");

        result.Success.Should().BeFalse();
        result.FriendlyMessage.Should().Be("SSCC not found.");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ConfirmSscc — delegates to command repo with correct parameters
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ConfirmSscc_DelegatesToCommandRepo()
    {
        var stub    = new StubInboundCommandRepo();
        var service = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver());

        service.ConfirmSscc(42, "SSCC001", "BAY01", Guid.NewGuid());

        stub.ReceiveInboundLineCalled.Should().BeTrue();
    }

    [Fact]
    public void ConfirmSscc_PassesExpectedUnitId()
    {
        var stub    = new StubInboundCommandRepo();
        var service = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver());

        service.ConfirmSscc(99, "SSCC001", "BAY01", Guid.NewGuid());

        stub.LastInboundExpectedUnitId.Should().Be(99);
    }

    [Fact]
    public void ConfirmSscc_PassesExternalRef()
    {
        var stub    = new StubInboundCommandRepo();
        var service = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver());

        service.ConfirmSscc(1, "SSCC_ABC", "BAY01", Guid.NewGuid());

        stub.LastExternalRef.Should().Be("SSCC_ABC");
    }

    [Fact]
    public void ConfirmSscc_PassesStagingBin()
    {
        var stub    = new StubInboundCommandRepo();
        var service = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver());

        service.ConfirmSscc(1, "SSCC001", "STAGING_BIN_A", Guid.NewGuid());

        stub.LastStagingBinCode.Should().Be("STAGING_BIN_A");
    }

    [Fact]
    public void ConfirmSscc_PassesClaimToken()
    {
        var stub    = new StubInboundCommandRepo();
        var service = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver());
        var token   = Guid.NewGuid();

        service.ConfirmSscc(1, "SSCC001", "BAY01", token);

        stub.LastClaimToken.Should().Be(token);
    }

    [Fact]
    public void ConfirmSscc_ReturnsRepoResult()
    {
        var stub = new StubInboundCommandRepo
        {
            ReceiveResult = OperationResult.Create(true, "SUCINBL01", "Received.")
        };

        var result = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver())
            .ConfirmSscc(1, "SSCC001", "BAY01", Guid.NewGuid());

        result.Success.Should().BeTrue();
        result.ResultCode.Should().Be("SUCINBL01");
    }

    [Fact]
    public void ConfirmSscc_WhenRepoFails_ReturnsFail()
    {
        var stub = new StubInboundCommandRepo
        {
            ReceiveResult = OperationResult.Create(false, "ERRINBL01", "Claim expired.")
        };

        var result = new InboundReceivingService(new StubInboundQueryRepo(), stub, new StubErrorMessageResolver())
            .ConfirmSscc(1, "SSCC001", "BAY01", Guid.NewGuid());

        result.Success.Should().BeFalse();
        result.FriendlyMessage.Should().Be("Claim expired.");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stubs — internal so they're visible within the test assembly only
// ─────────────────────────────────────────────────────────────────────────────

internal sealed class StubInboundQueryRepo : IInboundQueryRepository
{
    public bool   ValidateSsccCalled  { get; private set; }
    public string LastExternalRef     { get; private set; } = string.Empty;
    public string LastStagingBin      { get; private set; } = string.Empty;

    public SsccValidationDto ValidateSsccResult { get; set; } = new SsccValidationDto
    {
        Success = true, FriendlyMessage = "OK"
    };

    public SsccValidationDto ValidateSsccForInbound(
        string externalRef,
        string stagingBin,
        DateOnly? scannedBestBefore = null,
        string?   scannedBatch      = null)
    {
        ValidateSsccCalled = true;
        LastExternalRef    = externalRef;
        LastStagingBin     = stagingBin;
        return ValidateSsccResult;
    }

    public InboundSummaryDto GetInboundSummary(string inboundRef) => new();
    public int GetOutstandingSsccCount(string inboundRef) => 0;
    public IEnumerable<ActivatableInboundDto> GetActivatableInbounds() => [];
    public IEnumerable<InboundLineDto> GetReceivableLines(string inboundRef) => [];
    public IEnumerable<InboundReceiptDto> GetReceivableReceipts(string inboundRef) => [];
    public InboundLineByEanDto? GetReceivableLineByEan(string inboundRef, string ean) => null;
}

internal sealed class StubInboundCommandRepo : IInboundCommandRepository
{
    public bool    ReceiveInboundLineCalled     { get; private set; }
    public int?    LastInboundExpectedUnitId    { get; private set; }
    public string? LastExternalRef             { get; private set; }
    public string? LastStagingBinCode          { get; private set; }
    public Guid?   LastClaimToken              { get; private set; }

    public OperationResult ReceiveResult { get; set; } =
        OperationResult.Create(true, "SUCINBL01", "Received successfully.");

    public OperationResult ReceiveInboundLine(
        int       inboundLineId,
        int       receivedQty,
        string    stagingBinCode,
        int?      inboundExpectedUnitId = null,
        string?   externalRef          = null,
        string?   batchNumber          = null,
        DateTime? bestBeforeDate       = null,
        Guid?     claimToken           = null)
    {
        ReceiveInboundLineCalled  = true;
        LastInboundExpectedUnitId = inboundExpectedUnitId;
        LastExternalRef           = externalRef;
        LastStagingBinCode        = stagingBinCode;
        LastClaimToken            = claimToken;
        return ReceiveResult;
    }

    public OperationResult CreateInbound(string inboundRef, string supplierPartyCode, string? haulierPartyCode = null, DateTime? expectedArrivalAt = null)
        => OperationResult.Create(true, "SUCINB02", "Created.");

    public OperationResult AddInboundLine(string inboundRef, string skuCode, int expectedQty, string? batchNumber = null, DateTime? bestBeforeDate = null, string arrivalStockStatus = "AV")
        => OperationResult.Create(true, "SUCINBL02", "Created.");

    public OperationResult AddExpectedUnit(string inboundRef, string sscc, int quantity, string? batchNumber = null, DateTime? bestBeforeDate = null)
        => OperationResult.Create(true, "SUCINBU01", "Created.");

    public OperationResult ActivateInbound(int inboundId) =>
        OperationResult.Create(true, "SUC", "OK");

    public OperationResult ActivateInboundByRef(string inboundRef) =>
        OperationResult.Create(true, "SUC", "OK");

    public OperationResult ReverseInboundReceipt(
        int receiptId, string? reasonCode = null, string? reasonText = null) =>
        OperationResult.Create(true, "SUC", "OK");
}

internal sealed class StubErrorMessageResolver : IErrorMessageResolver
{
    public string Resolve(string code) => code;
}
