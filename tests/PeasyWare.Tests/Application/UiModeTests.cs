using FluentAssertions;
using PeasyWare.Application;
using Xunit;

namespace PeasyWare.Tests.Application;

public class UiModeTests
{
    [Fact]
    public void OnlyTrace_MeetsTraceThreshold()
    {
        var trace    = UiMode.Trace;
        var standard = UiMode.Standard;
        var minimal  = UiMode.Minimal;

        (trace    >= UiMode.Trace).Should().BeTrue();
        (standard >= UiMode.Trace).Should().BeFalse();
        (minimal  >= UiMode.Trace).Should().BeFalse();
    }
}
