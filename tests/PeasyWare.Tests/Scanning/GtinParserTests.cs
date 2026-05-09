using FluentAssertions;
using PeasyWare.Application.Scanning;
using Xunit;

namespace PeasyWare.Tests.Scanning;

/// <summary>
/// Unit tests for GtinParser.
///
/// Coverage:
///   - Parenthesis format (human-readable labels)
///   - Raw flat format (scanner output, no delimiters)
///   - FNC1-delimited format
///   - SSCC-only pallet labels
///   - Product label with GTIN + batch + BBE
///   - Combined labels (product + SSCC on one scan)
///   - Batch values containing digit sequences that look like AIs (regression: "SKU003BATCH")
///   - BBE date parsing (YYMMDD, day-00 = last of month, real day used as-is)
///   - Invalid / empty input
///   - IsProductScan / IsPalletScan flags
/// </summary>
public class GtinParserTests
{
    // ─────────────────────────────────────────────────────────────────────────
    // PALLET LABEL (SSCC only)
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Parse_PalletLabel_ParenthesisFormat_ExtractsSSCC()
    {
        var result = GtinParser.Parse("(00)300000000000000001(15)270331");

        result.IsValid.Should().BeTrue();
        result.IsPalletScan.Should().BeTrue();
        result.IsProductScan.Should().BeFalse();
        result.Sscc.Should().Be("300000000000000001");
    }

    [Fact]
    public void Parse_PalletLabel_ExtractsBBE_FromAI15()
    {
        var result = GtinParser.Parse("(00)300000000000000001(15)270331");

        result.BestBefore.Should().Be(new DateOnly(2027, 3, 31));
    }

    [Fact]
    public void Parse_PalletLabel_AI15_DayZero_ReturnsLastDayOfMonth()
    {
        // DD=00 means last day of month per GS1 spec
        var result = GtinParser.Parse("(00)300000000000000001(15)270200");

        result.BestBefore.Should().Be(new DateOnly(2027, 2, 28));
    }

    [Fact]
    public void Parse_PalletLabel_AI15_RealDay_UsedAsIs()
    {
        // DD=01 is a real day — GS1 spec says use it as-is, NOT last-of-month
        var result = GtinParser.Parse("(00)300000000000000001(15)270101");

        result.BestBefore.Should().Be(new DateOnly(2027, 1, 1));
    }

    [Fact]
    public void Parse_PalletLabel_AI17_ExpiryDate()
    {
        var result = GtinParser.Parse("(00)300000000000000001(17)270315");

        result.IsValid.Should().BeTrue();
        result.BestBefore.Should().Be(new DateOnly(2027, 3, 15));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRODUCT LABEL (GTIN + batch + BBE)
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Parse_ProductLabel_ParenthesisFormat_ExtractsGtin()
    {
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH");

        result.IsValid.Should().BeTrue();
        result.IsProductScan.Should().BeTrue();
        result.IsPalletScan.Should().BeFalse();
        result.Gtin.Should().Be("05556899874510");
    }

    [Fact]
    public void Parse_ProductLabel_ExtractsBatchCorrectly_WhenBatchContainsDigitSequences()
    {
        // Regression: "SKU003BATCH" was being truncated to "SKU" because
        // ReadVariable was stopping on "003" (matching AI prefix "00").
        // Fixed by removing IsKnownAiAt — FNC1 is the correct terminator.
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH");

        result.Batch.Should().Be("SKU003BATCH");
    }

    [Fact]
    public void Parse_ProductLabel_BatchWith_LeadingZeros_NotTruncated()
    {
        var result = GtinParser.Parse("(01)05010102200142(10)001440487A");

        result.Batch.Should().Be("001440487A");
    }

    [Fact]
    public void Parse_ProductLabel_BatchWith_AllDigits_NotTruncated()
    {
        var result = GtinParser.Parse("(01)05010102200142(10)00144048701");

        result.Batch.Should().Be("00144048701");
    }

    [Fact]
    public void Parse_ProductLabel_WithGtinAndBatch_NoSSCC()
    {
        var result = GtinParser.Parse("(01)05010102200142(10)BATCH001");

        result.Sscc.Should().BeNull();
        result.Gtin.Should().Be("05010102200142");
        result.Batch.Should().Be("BATCH001");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // COMBINED LABEL (product + SSCC on same barcode)
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Parse_CombinedLabel_ExtractsBothGtinAndSSCC()
    {
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH(00)300000000000000001(15)270331");

        result.IsValid.Should().BeTrue();
        result.Gtin.Should().Be("05556899874510");
        result.Sscc.Should().Be("300000000000000001");
        result.Batch.Should().Be("SKU003BATCH");
        result.BestBefore.Should().Be(new DateOnly(2027, 3, 31));
    }

    [Fact]
    public void Parse_CombinedLabel_IsProductScan_And_IsPalletScan_BothTrue()
    {
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH(00)300000000000000001");

        result.IsProductScan.Should().BeTrue();
        result.IsPalletScan.Should().BeTrue();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BBE DATE PARSING
    // GS1 spec: DD=00 → last day of month; DD=01+ → literal day
    // ─────────────────────────────────────────────────────────────────────────

    [Theory]
    [InlineData("(00)300000000000000001(15)261130", 2026, 11, 30)]  // real day 30
    [InlineData("(00)300000000000000001(15)270101", 2027, 1,  1)]   // real day 01 — must NOT become 31
    [InlineData("(00)300000000000000001(15)991231", 1999, 12, 31)]  // real day 31
    [InlineData("(00)300000000000000001(15)000101", 2000, 1,  1)]   // real day 01 — must NOT become 31
    [InlineData("(00)300000000000000001(15)491231", 2049, 12, 31)]  // YY=49 → 2049
    [InlineData("(00)300000000000000001(15)501231", 1950, 12, 31)]  // YY=50 → 1950
    public void Parse_BbeDate_YearMapping_IsCorrect(string input, int expectedYear, int expectedMonth, int expectedDay)
    {
        var result = GtinParser.Parse(input);

        result.BestBefore.Should().Be(new DateOnly(expectedYear, expectedMonth, expectedDay));
    }

    [Theory]
    [InlineData("(00)300000000000000001(15)270200", 2027, 2, 28)]  // DD=00 → last day of Feb 2027
    [InlineData("(00)300000000000000001(15)240200", 2024, 2, 29)]  // DD=00 → last day of Feb 2024 (leap year)
    [InlineData("(00)300000000000000001(15)270100", 2027, 1, 31)]  // DD=00 → last day of Jan
    public void Parse_BbeDate_DayZero_ReturnsLastDayOfMonth(string input, int expectedYear, int expectedMonth, int expectedDay)
    {
        var result = GtinParser.Parse(input);

        result.BestBefore.Should().Be(new DateOnly(expectedYear, expectedMonth, expectedDay));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REAL BRITVIC-STYLE BARCODES (from session test data)
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Parse_BritvicStyle_ProductLabel_SKU003()
    {
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH");

        result.IsValid.Should().BeTrue();
        result.Gtin.Should().Be("05556899874510");
        result.Batch.Should().Be("SKU003BATCH");
        result.IsPalletScan.Should().BeFalse();
        result.IsProductScan.Should().BeTrue();
    }

    [Fact]
    public void Parse_BritvicStyle_PalletLabel_WithBBE()
    {
        var result = GtinParser.Parse("(00)300000000000000001(15)270331");

        result.IsValid.Should().BeTrue();
        result.Sscc.Should().Be("300000000000000001");
        result.BestBefore.Should().Be(new DateOnly(2027, 3, 31));
        result.IsPalletScan.Should().BeTrue();
        result.IsProductScan.Should().BeFalse();
    }

    [Fact]
    public void Parse_OriginalBritvicLabel_AI10AI01()
    {
        var result = GtinParser.Parse("(01)05010102200142(10)001440487A");

        result.IsValid.Should().BeTrue();
        result.Gtin.Should().Be("05010102200142");
        result.Batch.Should().Be("001440487A");
    }

    [Fact]
    public void Parse_OriginalBritvicPalletLabel()
    {
        var result = GtinParser.Parse("(00)150101027125056378(15)261130");

        result.IsValid.Should().BeTrue();
        result.Sscc.Should().Be("150101027125056378");
        result.BestBefore.Should().Be(new DateOnly(2026, 11, 30));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INVALID / EDGE CASES
    // ─────────────────────────────────────────────────────────────────────────

    [Fact]
    public void Parse_NullInput_ReturnsInvalid()
    {
        var result = GtinParser.Parse(null);

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Parse_EmptyString_ReturnsInvalid()
    {
        var result = GtinParser.Parse(string.Empty);

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Parse_WhitespaceOnly_ReturnsInvalid()
    {
        var result = GtinParser.Parse("   ");

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public void Parse_PlainBinCode_ReturnsInvalid_AndNoFields()
    {
        // Plain Code-128 bin label — no GS1 AIs
        var result = GtinParser.Parse("R0201B");

        result.IsValid.Should().BeFalse();
        result.Sscc.Should().BeNull();
        result.Gtin.Should().BeNull();
    }

    [Fact]
    public void Parse_PlainSscc_NoParentheses_ExtractsSSCC()
    {
        // Raw 20-digit string: AI "00" prefix + 18-digit SSCC value
        var result = GtinParser.Parse("00300000000000000001");

        result.IsValid.Should().BeTrue();
        result.Sscc.Should().Be("300000000000000001");
    }

    [Fact]
    public void Parse_TildeAsFnc1_WorksLikeParenthesisFormat()
    {
        var result = GtinParser.Parse("(01)05556899874510(10)SKU003BATCH~(00)300000000000000001");

        result.IsValid.Should().BeTrue();
        result.Gtin.Should().Be("05556899874510");
        result.Sscc.Should().Be("300000000000000001");
    }

    [Fact]
    public void Parse_DoesNotThrow_OnUnrecognisedInput()
    {
        var act = () => GtinParser.Parse("%%%%NOT_A_BARCODE%%%%");

        act.Should().NotThrow();
    }

    // ── Ardagh Group label format ────────────────────────────────────────────
    // Real label from Ardagh Group (can manufacturer, customer: Britvic).
    // Three barcodes, none matching the standard Britvic format:
    //   Barcode 1: (02)04045907311343(11)260406(37)8073
    //   Barcode 2: (10)2604062414(21)128834
    //   Barcode 3: (00)640617550330318013

    [Fact]
    public void Parse_ArdaghBarcode1_ContainedGtinProductionDateQuantity()
    {
        var result = GtinParser.Parse("(02)04045907311343(11)260406(37)8073");

        result.IsValid.Should().BeTrue();
        result.ContainedGtin.Should().Be("04045907311343");
        result.ProductionDate.Should().Be(new DateOnly(2026, 4, 6));
        result.Quantity.Should().Be(8073);
        result.Sscc.Should().BeNull();
        result.Gtin.Should().BeNull();
        result.BestBefore.Should().BeNull();
    }

    [Fact]
    public void Parse_ArdaghBarcode2_BatchAndSerialNumber()
    {
        var result = GtinParser.Parse("(10)2604062414(21)128834");

        result.IsValid.Should().BeTrue();
        result.Batch.Should().Be("2604062414");
        result.SerialNumber.Should().Be("128834");
        result.Sscc.Should().BeNull();
    }

    [Fact]
    public void Parse_ArdaghBarcode2_RawFlat_SplitsAtAiBoundary()
    {
        // Raw scan without FNC1: "10" + batch + "21" + serial
        // Numeric-only heuristic should stop batch at AI "21" boundary
        var result = GtinParser.Parse("10260406241421128834");

        result.IsValid.Should().BeTrue();
        result.Batch.Should().Be("2604062414");
        result.SerialNumber.Should().Be("128834");
    }

    [Fact]
    public void Parse_ArdaghBarcode3_Sscc()
    {
        var result = GtinParser.Parse("(00)640617550330318013");

        result.IsValid.Should().BeTrue();
        result.Sscc.Should().Be("640617550330318013");
    }

    [Fact]
    public void Parse_ArdaghRawConcatenated_NoBrackets_ExtractsAllAIs()
    {
        // Raw string as a scanner would emit without parentheses or FNC1
        // 02+14digits + 11+6digits + 37+4digits
        var result = GtinParser.Parse("020404590731134311260406378073");

        result.IsValid.Should().BeTrue();
        result.ContainedGtin.Should().Be("04045907311343");
        result.ProductionDate.Should().Be(new DateOnly(2026, 4, 6));
        result.Quantity.Should().Be(8073);
    }

    [Fact]
    public void Parse_ArdaghRawWithTrailingZero_StillParses()
    {
        // Some scanners append a trailing character — parser should tolerate it
        var result = GtinParser.Parse("0204045907311343112604063780730");

        result.IsValid.Should().BeTrue();
        result.ContainedGtin.Should().Be("04045907311343");
        result.ProductionDate.Should().Be(new DateOnly(2026, 4, 6));
    }

    [Fact]
    public void Parse_ArdaghFullScan_AllThreeBarcodesIndividually_AllValid()
    {
        // Simulate operator scanning all three barcodes in sequence
        var b1 = GtinParser.Parse("(02)04045907311343(11)260406(37)8073");
        var b2 = GtinParser.Parse("(10)2604062414(21)128834");
        var b3 = GtinParser.Parse("(00)640617550330318013");

        b1.IsValid.Should().BeTrue();
        b2.IsValid.Should().BeTrue();
        b3.IsValid.Should().BeTrue();

        // Key fields across the three scans
        b1.ContainedGtin.Should().Be("04045907311343");
        b1.ProductionDate.Should().Be(new DateOnly(2026, 4, 6));
        b1.Quantity.Should().Be(8073);
        b2.Batch.Should().Be("2604062414");
        b2.SerialNumber.Should().Be("128834");
        b3.Sscc.Should().Be("640617550330318013");
    }

    [Fact]
    public void EffectiveGtin_ReturnsContainedGtin_WhenOnlyAi02Present()
    {
        var result = GtinParser.Parse("(02)04045907311343");

        result.IsValid.Should().BeTrue();
        result.Gtin.Should().BeNull();
        result.ContainedGtin.Should().Be("04045907311343");
        result.EffectiveGtin.Should().Be("04045907311343");
    }

    [Fact]
    public void EffectiveGtin_PrefersAi01_WhenBothPresent()
    {
        var result = GtinParser.Parse("(01)05010102200142(02)04045907311343");

        result.IsValid.Should().BeTrue();
        result.Gtin.Should().Be("05010102200142");
        result.ContainedGtin.Should().Be("04045907311343");
        result.EffectiveGtin.Should().Be("05010102200142");
    }
}
