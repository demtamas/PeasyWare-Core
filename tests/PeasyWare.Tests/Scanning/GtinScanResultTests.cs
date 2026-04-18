using FluentAssertions;
using PeasyWare.Application.Scanning;
using Xunit;

namespace PeasyWare.Tests.Scanning;

/// <summary>
/// Tests for GtinScanResult value object.
/// Covers: IsPalletScan / IsProductScan flags, Invalid / Empty factories,
/// combined label flag behaviour, and ErrorReason population.
/// </summary>
public class GtinScanResultTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // IsPalletScan / IsProductScan flags
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void IsPalletScan_WhenSsccPresent_ReturnsTrue()
    {
        var result = new GtinScanResult { Sscc = "300000000000000001", IsValid = true };
        result.IsPalletScan.Should().BeTrue();
    }

    [Fact]
    public void IsPalletScan_WhenSsccNull_ReturnsFalse()
    {
        var result = new GtinScanResult { Gtin = "05556899874510", IsValid = true };
        result.IsPalletScan.Should().BeFalse();
    }

    [Fact]
    public void IsProductScan_WhenGtinPresent_ReturnsTrue()
    {
        var result = new GtinScanResult { Gtin = "05556899874510", IsValid = true };
        result.IsProductScan.Should().BeTrue();
    }

    [Fact]
    public void IsProductScan_WhenGtinNull_ReturnsFalse()
    {
        var result = new GtinScanResult { Sscc = "300000000000000001", IsValid = true };
        result.IsProductScan.Should().BeFalse();
    }

    [Fact]
    public void BothFlags_WhenSsccAndGtinPresent_BothTrue()
    {
        // Combined label — product barcode + pallet SSCC on same scan
        var result = new GtinScanResult
        {
            Sscc    = "300000000000000001",
            Gtin    = "05556899874510",
            IsValid = true
        };

        result.IsPalletScan.Should().BeTrue();
        result.IsProductScan.Should().BeTrue();
    }

    [Fact]
    public void BothFlags_WhenNeitherSsccNorGtin_BothFalse()
    {
        // Batch-only scan (unusual but valid GS1 label)
        var result = new GtinScanResult { Batch = "BATCH001", IsValid = true };

        result.IsPalletScan.Should().BeFalse();
        result.IsProductScan.Should().BeFalse();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Invalid factory
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Invalid_SetsIsValidFalse()
    {
        var result = GtinScanResult.Invalid("test reason");
        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Invalid_PopulatesErrorReason()
    {
        var result = GtinScanResult.Invalid("Scan input is empty.");
        result.ErrorReason.Should().Be("Scan input is empty.");
    }

    [Fact]
    public void Invalid_AllDataFieldsAreNull()
    {
        var result = GtinScanResult.Invalid("any reason");
        result.Sscc.Should().BeNull();
        result.Gtin.Should().BeNull();
        result.Batch.Should().BeNull();
        result.BestBefore.Should().BeNull();
        result.Quantity.Should().BeNull();
    }

    [Fact]
    public void Invalid_IsPalletScan_ReturnsFalse()
    {
        GtinScanResult.Invalid("reason").IsPalletScan.Should().BeFalse();
    }

    [Fact]
    public void Invalid_IsProductScan_ReturnsFalse()
    {
        GtinScanResult.Invalid("reason").IsProductScan.Should().BeFalse();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Empty factory
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Empty_SetsIsValidFalse()
    {
        var result = GtinScanResult.Empty();
        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Empty_PopulatesErrorReason()
    {
        var result = GtinScanResult.Empty();
        result.ErrorReason.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public void Empty_AllDataFieldsAreNull()
    {
        var result = GtinScanResult.Empty();
        result.Sscc.Should().BeNull();
        result.Gtin.Should().BeNull();
        result.Batch.Should().BeNull();
        result.BestBefore.Should().BeNull();
        result.Quantity.Should().BeNull();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Valid result — field population
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ValidResult_ErrorReasonIsNull()
    {
        var result = new GtinScanResult
        {
            Sscc    = "300000000000000001",
            IsValid = true
        };

        result.ErrorReason.Should().BeNull();
    }

    [Fact]
    public void ValidResult_AllOptionalFieldsCanBeNull()
    {
        // A valid SSCC-only scan has no GTIN, batch, BBE, or quantity
        var result = new GtinScanResult
        {
            Sscc    = "300000000000000001",
            IsValid = true
        };

        result.Gtin.Should().BeNull();
        result.Batch.Should().BeNull();
        result.BestBefore.Should().BeNull();
        result.Quantity.Should().BeNull();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Round-trip through GtinParser — flags match parsed content
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void ParsedPalletLabel_IsPalletScan_True_IsProductScan_False()
    {
        var result = GtinParser.Parse("(00)300000000000000001(15)270331");
        result.IsPalletScan.Should().BeTrue();
        result.IsProductScan.Should().BeFalse();
    }

    [Fact]
    public void ParsedProductLabel_IsProductScan_True_IsPalletScan_False()
    {
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH");
        result.IsProductScan.Should().BeTrue();
        result.IsPalletScan.Should().BeFalse();
    }

    [Fact]
    public void ParsedCombinedLabel_BothFlagsTrue()
    {
        var result = GtinParser.Parse("(00)300000000000000001(01)05556899874510(10)SKU003BATCH");
        result.IsPalletScan.Should().BeTrue();
        result.IsProductScan.Should().BeTrue();
    }

    [Fact]
    public void ParsedEmptyString_IsValid_False()
    {
        var result = GtinParser.Parse(string.Empty);
        result.IsValid.Should().BeFalse();
        result.ErrorReason.Should().NotBeNullOrWhiteSpace();
    }
}
