using PeasyWare.Application;
using Xunit;

namespace PeasyWare.Tests.Application;

public class OperationResultTests
{
    // ==========================================================
    // Success / failure flag
    // ==========================================================

    [Fact]
    public void Create_Success_True_SetsSuccessTrue()
    {
        var result = OperationResult.Create(true, "SUCORD01", "Order created.");
        Assert.True(result.Success);
    }

    [Fact]
    public void Create_Success_False_SetsSuccessFalse()
    {
        var result = OperationResult.Create(false, "ERRORD01", "Order not found.");
        Assert.False(result.Success);
    }

    // ==========================================================
    // Result code
    // ==========================================================

    [Fact]
    public void Create_SetsResultCode()
    {
        var result = OperationResult.Create(true, "SUCINB01", "OK.");
        Assert.Equal("SUCINB01", result.ResultCode);
    }

    [Fact]
    public void Create_ResultCode_PreservesCase()
    {
        var result = OperationResult.Create(false, "errord01", "Lower case code.");
        Assert.Equal("errord01", result.ResultCode);
    }

    // ==========================================================
    // Friendly message
    // ==========================================================

    [Fact]
    public void Create_SetsFriendlyMessage()
    {
        var result = OperationResult.Create(true, "SUCORD01", "Order created successfully.");
        Assert.Equal("Order created successfully.", result.FriendlyMessage);
    }

    [Fact]
    public void Create_EmptyMessage_IsAllowed()
    {
        var result = OperationResult.Create(true, "SUC", "");
        Assert.Equal("", result.FriendlyMessage);
    }

    // ==========================================================
    // Entity / parent ID defaults
    // ==========================================================

    [Fact]
    public void Create_DefaultEntityId_IsZero()
    {
        var result = OperationResult.Create(true, "SUC", "OK.");
        Assert.Equal(0, result.EntityId);
    }

    [Fact]
    public void Create_DefaultParentId_IsZero()
    {
        var result = OperationResult.Create(true, "SUC", "OK.");
        Assert.Equal(0, result.ParentId);
    }

    [Fact]
    public void Create_WithEntityId_SetsIt()
    {
        var result = OperationResult.Create(true, "SUCORD01", "OK.", entityId: 42);
        Assert.Equal(42, result.EntityId);
    }

    [Fact]
    public void Create_WithParentId_SetsIt()
    {
        var result = OperationResult.Create(true, "SUCORD01", "OK.", entityId: 5, parentId: 99);
        Assert.Equal(99, result.ParentId);
    }

    [Fact]
    public void Create_EntityIdAndParentIdAreIndependent()
    {
        var result = OperationResult.Create(true, "SUC", "OK.", entityId: 7, parentId: 13);
        Assert.Equal(7,  result.EntityId);
        Assert.Equal(13, result.ParentId);
    }

    // ==========================================================
    // Immutability
    // ==========================================================

    [Fact]
    public void TwoResults_WithSameArgs_AreIndependent()
    {
        var r1 = OperationResult.Create(true,  "SUCORD01", "Created.", entityId: 1);
        var r2 = OperationResult.Create(false, "ERRORD01", "Failed.",  entityId: 2);

        Assert.True(r1.Success);
        Assert.False(r2.Success);
        Assert.Equal(1, r1.EntityId);
        Assert.Equal(2, r2.EntityId);
        Assert.Equal("SUCORD01", r1.ResultCode);
        Assert.Equal("ERRORD01", r2.ResultCode);
    }

    // ==========================================================
    // Error code pattern conventions (ERR / WAR / SUC prefix)
    // ==========================================================

    [Theory]
    [InlineData("SUCAUTH01",  true)]
    [InlineData("SUCINB01",   true)]
    [InlineData("SUCORD01",   true)]
    [InlineData("SUCSHIP01",  true)]
    [InlineData("SUCTASK01",  true)]
    [InlineData("ERRAUTH01",  false)]
    [InlineData("ERRINB01",   false)]
    [InlineData("ERRORD01",   false)]
    [InlineData("ERRALLOC01", false)]
    public void Create_SuccessFlag_MatchesCodePrefix(string code, bool expectedSuccess)
    {
        var result = OperationResult.Create(expectedSuccess, code, "msg");
        Assert.Equal(expectedSuccess, result.Success);
        Assert.Equal(code, result.ResultCode);
    }

    // ==========================================================
    // Not null
    // ==========================================================

    [Fact]
    public void Create_ResultCode_IsNeverNull()
    {
        var result = OperationResult.Create(true, "SUC", "OK.");
        Assert.NotNull(result.ResultCode);
    }

    [Fact]
    public void Create_FriendlyMessage_IsNeverNull()
    {
        var result = OperationResult.Create(false, "ERR", "Something went wrong.");
        Assert.NotNull(result.FriendlyMessage);
    }
}
