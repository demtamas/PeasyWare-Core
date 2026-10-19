using FluentAssertions;
using PeasyWare.Application.Dto;
using Xunit;

namespace PeasyWare.Tests.Application;

/// <summary>
/// The small rules the count screens lean on, kept in the DTOs so the CLI and the
/// Desktop cannot disagree about them: what can be applied, what still needs a
/// person, what a sweep is, and how a refused scan is recognised.
/// </summary>
public class CountDtoTests
{
    // ─────────────────────────────────────────────────────────────────────
    // CountFindingDto
    // ─────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("QTY_DIFFERENCE", true)]
    [InlineData("MISSING",        true)]
    [InlineData("MISPLACED",      true)]
    [InlineData("UNKNOWN_UNIT",   false)]   // nothing to apply - declined to acknowledge
    [InlineData("NOT_CORRECTED",  false)]   // shipped / reversed / rule-blocked pallets
    [InlineData("RECORD_CORRECTED", false)] // an empty-bin count's own correction
    public void Finding_IsActionable_OnlyForQuantityMissingAndMisplaced(string code, bool expected)
    {
        new CountFindingDto { FindingCode = code }.IsActionable.Should().Be(expected);
    }

    [Fact]
    public void Finding_NeedsReview_WhileUndecided()
    {
        new CountFindingDto { FindingCode = "MISSING" }.NeedsReview.Should().BeTrue();
        new CountFindingDto { FindingCode = "UNKNOWN_UNIT" }.NeedsReview.Should().BeTrue();
        new CountFindingDto { FindingCode = "NOT_CORRECTED" }.NeedsReview.Should().BeTrue();
    }

    [Theory]
    [InlineData("APPLIED")]
    [InlineData("DECLINED")]
    public void Finding_NoLongerNeedsReview_OnceApplied_OrDeclined(string resolution)
    {
        var finding = new CountFindingDto { FindingCode = "QTY_DIFFERENCE", ResolutionCode = resolution };

        finding.IsResolved.Should().BeTrue();
        finding.NeedsReview.Should().BeFalse();
    }

    [Fact]
    public void Finding_RecordCorrected_NeverNeedsReview()
    {
        new CountFindingDto { FindingCode = "RECORD_CORRECTED" }.NeedsReview.Should().BeFalse();
    }

    [Fact]
    public void Finding_IsNotResolved_ByDefault()
    {
        new CountFindingDto { FindingCode = "MISPLACED" }.IsResolved.Should().BeFalse();
    }

    // ─────────────────────────────────────────────────────────────────────
    // CountSessionDto
    // ─────────────────────────────────────────────────────────────────────

    [Fact]
    public void Session_BinCountSweep_IsASweep()
    {
        var session = new CountSessionDto { CountTypeCode = "BIN_COUNT", ScopeCode = "ALL", StorageTypeCode = null };

        session.IsSweep.Should().BeTrue();
        session.IsAdHoc.Should().BeFalse();
        session.ScopeText.Should().Be("All storage types");
    }

    [Fact]
    public void Session_AdHocCount_IsNotASweep_EvenWithNoStorageType()
    {
        // Both have no storage type; only the scope tells them apart
        var session = new CountSessionDto { CountTypeCode = "BIN_COUNT", ScopeCode = "ADHOC", StorageTypeCode = null };

        session.IsAdHoc.Should().BeTrue();
        session.IsSweep.Should().BeFalse();
        session.ScopeText.Should().Be("Ad hoc (selected bins)");
    }

    [Fact]
    public void Session_BinCountOfAStorageType_IsNeitherSweepNorAdHoc()
    {
        var session = new CountSessionDto { CountTypeCode = "BIN_COUNT", ScopeCode = "STORAGE_TYPE", StorageTypeCode = "RACK" };

        session.IsSweep.Should().BeFalse();
        session.IsAdHoc.Should().BeFalse();
        session.ScopeText.Should().Be("RACK");
    }

    [Fact]
    public void Session_EmptyBinCheck_IsNeverASweepOrAdHoc()
    {
        // The default scope is STORAGE_TYPE, which is what an empty-bin check is
        var session = new CountSessionDto { CountTypeCode = "EMPTY_BIN", StorageTypeCode = "RACK" };

        session.IsSweep.Should().BeFalse();
        session.IsAdHoc.Should().BeFalse();
        session.ScopeText.Should().Be("RACK");
    }

    [Theory]
    [InlineData("REVIEW",   true)]
    [InlineData("OPEN",     false)]
    [InlineData("COMPLETE", false)]
    [InlineData("CLOSED",   false)]
    public void Session_AwaitsReview_OnlyInReview(string status, bool expected)
    {
        new CountSessionDto { StatusCode = status }.AwaitsReview.Should().Be(expected);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Scan / finish results
    // ─────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("ERRCNT16", true)]
    [InlineData("errcnt16", true)]    // codes are compared without regard to case
    [InlineData("ERRCNT15", false)]
    [InlineData("SUCCNT11", false)]
    [InlineData("WARNCNT10", false)]  // needs confirmation is not an expired hold
    public void Scan_HoldExpired_OnlyForErrCnt16(string code, bool expected)
    {
        new BinCountScanResult { ResultCode = code }.HoldExpired.Should().Be(expected);
    }

    [Theory]
    [InlineData(0, false)]
    [InlineData(1, true)]
    [InlineData(5, true)]
    public void Finish_HasDifferences_WhenAnyWereRecorded(int differences, bool expected)
    {
        new BinCountFinishResult { Differences = differences }.HasDifferences.Should().Be(expected);
    }
}
