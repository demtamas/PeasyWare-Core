using PeasyWare.API.Middleware;
using PeasyWare.Infrastructure.Bootstrap;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// ── Services ──────────────────────────────────────────────────────────────
builder.Services.AddControllers()
    .AddJsonOptions(o =>
    {
        // Accept null for nullable string properties — prevents PowerShell seed
        // serialisation issues where $null becomes an unexpected JSON type
        o.JsonSerializerOptions.DefaultIgnoreCondition =
            JsonIgnoreCondition.WhenWritingNull;
        o.JsonSerializerOptions.NumberHandling =
            JsonNumberHandling.AllowReadingFromString;
    });

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
