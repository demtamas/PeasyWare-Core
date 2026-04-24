namespace PeasyWare.API.Middleware;

/// <summary>
/// Validates X-Api-Key header against PEASYWARE_API_KEY env var.
/// Swagger endpoints bypass auth in DEBUG builds.
/// </summary>
public sealed class ApiKeyMiddleware
{
    private const string HeaderName = "X-Api-Key";
    private const string EnvVarName = "PEASYWARE_API_KEY";

    private readonly RequestDelegate _next;
    private readonly string          _apiKey;

    public ApiKeyMiddleware(RequestDelegate next)
    {
        _next   = next;
        _apiKey = Environment.GetEnvironmentVariable(EnvVarName)
                  ?? throw new InvalidOperationException(
                      $"Required environment variable '{EnvVarName}' is not set.");
    }

    public async Task InvokeAsync(HttpContext context)
    {
#if DEBUG
        if (context.Request.Path.StartsWithSegments("/swagger") ||
            context.Request.Path.StartsWithSegments("/openapi"))
        {
            await _next(context);
            return;
        }
#endif
        if (!context.Request.Headers.TryGetValue(HeaderName, out var incoming)
            || incoming != _apiKey)
        {
            context.Response.StatusCode  = StatusCodes.Status401Unauthorized;
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsync(
                "{\"success\":false,\"resultCode\":\"ERRAPI01\",\"message\":\"Invalid or missing API key.\"}");
            return;
        }

        await _next(context);
    }
}
