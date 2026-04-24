using System;

namespace PeasyWare.Infrastructure.Bootstrap;

public static class BootstrapLoader
{
    private const string EnvVarName = "PEASYWARE_DB";

    public static BootstrapConfig Load()
    {
        // 1️⃣ Environment variable (preferred)
        var fromEnv = Environment.GetEnvironmentVariable(EnvVarName);
        if (!string.IsNullOrWhiteSpace(fromEnv))
            return new BootstrapConfig(fromEnv);

        // 2️⃣ DEV fallback — only available in DEBUG builds
        // In release builds, missing env var is a hard failure.
        // A deployment that forgets PEASYWARE_DB must fail loudly.
#if DEBUG
        var devFallback =
            "Server = localhost; Database = Pw_Core_DEV; Trusted_Connection = True; TrustServerCertificate = True;";

        return new BootstrapConfig(devFallback);
#else
        throw new InvalidOperationException(
            $"Required environment variable '{EnvVarName}' is not set. " +
            $"Set it to a valid SQL Server connection string before starting the application.");
#endif
    }
}
