namespace PeasyWare.Infrastructure.Bootstrap;

/// <summary>
/// Minimal configuration required to reach the database.
/// Loaded before RuntimeSettings.
/// </summary>
public sealed class BootstrapConfig
{
    public string ConnectionString { get; }

    public BootstrapConfig(string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new InvalidOperationException("Database connection string is missing.");

        ConnectionString = connectionString;
    }
}

