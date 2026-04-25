namespace PeasyWare.Tools;

/// <summary>
/// Resolves runtime configuration for pwtools.
/// Connection string from PEASYWARE_DB — same convention as the main apps.
/// Scripts root resolved relative to the solution root (two levels up from the binary).
/// </summary>
internal static class ToolsConfig
{
    private const string DbEnvVar = "PEASYWARE_DB";

    public static string GetConnectionString()
    {
        var cs = Environment.GetEnvironmentVariable(DbEnvVar);

        if (!string.IsNullOrWhiteSpace(cs))
            return cs;

#if DEBUG
        return "Server=localhost;Database=PW_Core_DEV;Trusted_Connection=True;TrustServerCertificate=True;";
#else
        throw new InvalidOperationException(
            $"Required environment variable '{DbEnvVar}' is not set. " +
            $"Set it to a valid SQL Server connection string before running pwtools.");
#endif
    }

    /// <summary>
    /// Returns the absolute path to the Database/Scripts folder.
    /// Walks up from the binary location to find the solution root
    /// (identified by the presence of PeasyWare.sln).
    /// </summary>
    public static string GetScriptsRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);

        while (dir != null)
        {
            if (dir.GetFiles("PeasyWare.sln").Length > 0)
                return Path.Combine(dir.FullName, "Database", "Scripts");

            dir = dir.Parent;
        }

        throw new InvalidOperationException(
            "Could not locate solution root (PeasyWare.sln). " +
            "Run pwtools from within the PeasyWare repository.");
    }

    public static string GetDatabaseRoot()
    {
        var scripts = GetScriptsRoot();
        return Path.GetDirectoryName(scripts)!;
    }
}
