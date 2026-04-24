namespace PeasyWare.API.Responses;

/// <summary>
/// Standard API response envelope.
/// Every endpoint returns this shape — callers always get
/// success, resultCode, message, and optionally a typed data payload.
/// </summary>
public sealed class ApiResponse<T>
{
    public bool    Success    { get; init; }
    public string  ResultCode { get; init; } = null!;
    public string  Message    { get; init; } = null!;
    public T?      Data       { get; init; }

    public static ApiResponse<T> Ok(string resultCode, string message, T data) => new()
    {
        Success    = true,
        ResultCode = resultCode,
        Message    = message,
        Data       = data
    };

    public static ApiResponse<T> Fail(string resultCode, string message) => new()
    {
        Success    = false,
        ResultCode = resultCode,
        Message    = message,
        Data       = default
    };
}

/// <summary>
/// Non-generic convenience for mutations that return no data payload.
/// </summary>
public sealed class ApiResponse
{
    public bool   Success    { get; init; }
    public string ResultCode { get; init; } = null!;
    public string Message    { get; init; } = null!;

    public static ApiResponse Ok(string resultCode, string message) => new()
    {
        Success    = true,
        ResultCode = resultCode,
        Message    = message
    };

    public static ApiResponse Fail(string resultCode, string message) => new()
    {
        Success    = false,
        ResultCode = resultCode,
        Message    = message
    };

    public static ApiResponse FromResult(PeasyWare.Application.OperationResult result) => new()
    {
        Success    = result.Success,
        ResultCode = result.ResultCode,
        Message    = result.FriendlyMessage
    };
}
