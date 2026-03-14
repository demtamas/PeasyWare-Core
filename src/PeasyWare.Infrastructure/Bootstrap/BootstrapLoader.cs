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

        // 2️⃣ DEV fallback (explicit, visible, removable)
        var devFallback =
            "Server = localhost; Database = Pw_Core_DEV; Trusted_Connection = True; TrustServerCertificate = True;";

        return new BootstrapConfig(devFallback);
    }
}
