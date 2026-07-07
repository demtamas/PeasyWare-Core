using PeasyWare.Application.Utilities;
using Xunit;

namespace PeasyWare.Tests.Application;

public sealed class WildcardMatcherTests
{
    // ── No wildcards — falls back to substring ──────────────────────────────

    [Fact]
    public void NoWildcard_SubstringMatch_Succeeds()
        => Assert.True(WildcardMatcher.Matches("R0101A", "R01"));

    [Fact]
    public void NoWildcard_CaseInsensitive()
        => Assert.True(WildcardMatcher.Matches("R0101A", "r01"));

    [Fact]
    public void NoWildcard_NoMatch()
        => Assert.False(WildcardMatcher.Matches("R0101A", "BULK"));

    [Fact]
    public void EmptyPattern_MatchesEverything()
        => Assert.True(WildcardMatcher.Matches("R0101A", ""));

    // ── * wildcard ─────────────────────────────────────────────────────────

    [Fact]
    public void Asterisk_SuffixMatch_FloorLevel()
        => Assert.True(WildcardMatcher.Matches("R0101A", "*A"));

    [Fact]
    public void Asterisk_SuffixMatch_TopLevel()
        => Assert.True(WildcardMatcher.Matches("R0101D", "*D"));

    [Fact]
    public void Asterisk_SuffixMatch_WrongLevel()
        => Assert.False(WildcardMatcher.Matches("R0101A", "*D"));

    [Fact]
    public void Asterisk_PrefixMatch()
        => Assert.True(WildcardMatcher.Matches("R0101A", "R01*"));

    [Fact]
    public void Asterisk_PrefixNoMatch()
        => Assert.False(WildcardMatcher.Matches("R0201A", "R01*"));

    [Fact]
    public void Asterisk_BothEnds()
        => Assert.True(WildcardMatcher.Matches("R0101A", "*010*"));

    [Fact]
    public void Asterisk_StandaloneMatchesAll()
        => Assert.True(WildcardMatcher.Matches("ANYTHING", "*"));

    [Fact]
    public void Asterisk_CaseInsensitive()
        => Assert.True(WildcardMatcher.Matches("R0101A", "*a"));

    // ── ? wildcard ─────────────────────────────────────────────────────────

    [Fact]
    public void QuestionMark_SingleCharMatch()
        => Assert.True(WildcardMatcher.Matches("R0101A", "R0101?"));

    [Fact]
    public void QuestionMark_TooShort()
        => Assert.False(WildcardMatcher.Matches("R010", "R0101?"));

    [Fact]
    public void QuestionMark_Mixed()
        => Assert.True(WildcardMatcher.Matches("BAY01", "BAY??"));

    // ── Real demo bin codes ─────────────────────────────────────────────────

    [Fact]
    public void RealData_FloorBins_StarA()
    {
        var floorBins  = new[] { "R0101A", "R0201A", "R0301A", "R0401A" };
        var nonFloor   = new[] { "R0101B", "R0101C", "R0101D" };

        Assert.All(floorBins, b => Assert.True(WildcardMatcher.Matches(b, "*A")));
        Assert.All(nonFloor,  b => Assert.False(WildcardMatcher.Matches(b, "*A")));
    }

    [Fact]
    public void RealData_Aisle1_R01Star()
    {
        var aisle1    = new[] { "R0101A", "R0101B", "R0101C", "R0101D" };
        var aisle2    = new[] { "R0201A", "R0201B" };

        Assert.All(aisle1, b => Assert.True(WildcardMatcher.Matches(b, "R01*")));
        Assert.All(aisle2, b => Assert.False(WildcardMatcher.Matches(b, "R01*")));
    }

    [Fact]
    public void RealData_StagingBays_BAYStar()
    {
        Assert.True(WildcardMatcher.Matches("BAY01", "BAY*"));
        Assert.True(WildcardMatcher.Matches("BAY12", "BAY*"));
        Assert.False(WildcardMatcher.Matches("BULK01", "BAY*"));
    }
}
