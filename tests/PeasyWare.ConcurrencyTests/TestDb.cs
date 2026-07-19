using Microsoft.Data.SqlClient;

namespace PeasyWare.ConcurrencyTests;

/// <summary>
/// Shared DB helper for the concurrency harness.
///
/// Deliberately bypasses the C# repository/session layer (SessionGuard,
/// RepositoryFactory, etc.) and talks straight to the stored procedures
/// via raw ADO.NET. What's under test here is SQL Server's own locking
/// behaviour inside the SPs, not the app's session plumbing - going
/// through the full login flow per simulated operator would add a lot
/// of unrelated surface area without testing anything additional.
///
/// Requires PEASYWARE_DB to be set, same as every other PeasyWare project.
/// </summary>
public static class TestDb
{
    public static string ConnectionString =>
        Environment.GetEnvironmentVariable("PEASYWARE_DB")
        ?? throw new InvalidOperationException(
            "PEASYWARE_DB is not set. The concurrency harness needs a real, " +
            "seeded database - it is not mockable, since what's under test " +
            "is SQL Server's own lock behaviour.");

    public static SqlConnection OpenConnection()
    {
        var conn = new SqlConnection(ConnectionString);
        conn.Open();
        return conn;
    }

    public static int ExecuteScalarInt(string sql, Action<SqlCommand>? bind = null)
    {
        using var conn = OpenConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        bind?.Invoke(cmd);
        var result = cmd.ExecuteScalar();
        return result is null or DBNull ? 0 : Convert.ToInt32(result);
    }

    public static void ExecuteNonQuery(string sql, Action<SqlCommand>? bind = null)
    {
        using var conn = OpenConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = sql;
        bind?.Invoke(cmd);
        cmd.ExecuteNonQuery();
    }
}
