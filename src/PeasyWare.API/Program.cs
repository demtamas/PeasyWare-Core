using PeasyWare.API.Middleware;
using PeasyWare.Infrastructure.Bootstrap;

var builder = WebApplication.CreateBuilder(args);

// ── Services ──────────────────────────────────────────────────────────────
builder.Services.AddControllers();

var runtime = AppRuntime.CreateForApi();
builder.Services.AddSingleton(runtime);

#if DEBUG
// Use built-in .NET 10 OpenAPI — no Swashbuckle dependency needed
builder.Services.AddOpenApi();
#endif

// ── Pipeline ──────────────────────────────────────────────────────────────
var app = builder.Build();

#if DEBUG
app.MapOpenApi();

// Swagger UI via scalar (lightweight, no Swashbuckle)
app.MapGet("/swagger", () => Results.Redirect("/openapi/v1.json"))
   .ExcludeFromDescription();
#endif

app.UseMiddleware<ApiKeyMiddleware>();
app.MapControllers();

app.Run();
