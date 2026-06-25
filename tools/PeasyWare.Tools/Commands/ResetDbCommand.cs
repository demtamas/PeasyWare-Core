using Microsoft.Data.SqlClient;

namespace PeasyWare.Tools.Commands;

/// <summary>
/// Drops and recreates the database by executing all scripts in Database/Scripts/
/// in alphanumeric order via sqlcmd.
///
/// Requires --confirm flag. In DEBUG builds defaults to DEV database.
/// Refuses to run in Release without explicit --env PROD flag.
///
/// Usage:
///   pwtools reset-db --confirm
///   pwtools reset-db --confirm --env PROD
///   pwtools reset-db --confirm --no-seed   (schema + structural SPs only, skips Database/Scripts/900_seed)
///   pwtools reset-db --confirm --no-demo   (keep settings/roles/admin user/locations, skip demo parties)
/// </summary>
internal static class ResetDbCommand
{
    public static int Run(string[] args)
    {
        var confirm = args.Contains("--confirm");
        var noSeed  = args.Contains("--no-seed");
        var noDemo  = args.Contains("--no-demo");
        var env     = args.Contains("--env") ? args[Array.IndexOf(args, "--env") + 1] : "DEV";

        if (!confirm)
        {
            Console.WriteLine("ERROR: --confirm flag required for reset-db.");
            Console.WriteLine("Usage: pwtools reset-db --confirm [--env DEV|PROD]");
            return 1;
        }

#if !DEBUG
        if (env != "PROD")
        {
            Console.WriteLine("ERROR: Release build requires --env PROD to prevent accidental resets.");
            return 1;
        }

        Console.Write("Type 'RESET' to confirm production database destruction: ");
        var typed = Console.ReadLine()?.Trim();
        if (typed != "RESET")
        {
            Console.WriteLine("Aborted.");
            return 1;
        }
#endif

        string cs;
        string scriptsRoot;

        try
        {
            cs          = ToolsConfig.GetConnectionString();
            scriptsRoot = ToolsConfig.GetScriptsRoot();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR: {ex.Message}");
            return 1;
        }

        if (!Directory.Exists(scriptsRoot))
        {
            Console.WriteLine($"ERROR: Scripts directory not found: {scriptsRoot}");
            return 1;
        }

        // Check sqlcmd is available
        var sqlcmd = FindSqlCmd();
        if (sqlcmd is null)
        {
            Console.WriteLine("ERROR: sqlcmd not found on PATH.");
            Console.WriteLine("Install SQL Server command-line tools or add sqlcmd to PATH.");
            return 1;
        }

        var scripts = CollectScripts(scriptsRoot);

        if (noSeed)
        {
            scripts = scripts
                .Where(s => !Path.GetDirectoryName(s)!.EndsWith("900_seed", StringComparison.OrdinalIgnoreCase))
                .ToList();
        }
        else if (noDemo)
        {
            scripts = scripts
                .Where(s => !Path.GetFileName(s).Contains("_demo_", StringComparison.OrdinalIgnoreCase)
                         && !Path.GetFileName(s).StartsWith("081_demo", StringComparison.OrdinalIgnoreCase))
                .ToList();
        }

        // If Scripts/ only has a README or is otherwise empty,
        // fall back to the AllInOne
        var realScripts = scripts.Where(s =>
            !Path.GetFileName(s).Equals("README.sql", StringComparison.OrdinalIgnoreCase))
            .ToList();

        if (realScripts.Count == 0)
        {
            var allInOne = Path.Combine(ToolsConfig.GetDatabaseRoot(), "DEV", "DEV_AllInOneInOneGo.sql");
            if (File.Exists(allInOne))
            {
                Console.WriteLine("Scripts/ not yet populated — falling back to DEV_AllInOneInOneGo.sql");
                realScripts = new List<string> { allInOne };
            }
            else
            {
                Console.WriteLine("ERROR: No scripts found and no AllInOne fallback available.");
                return 1;
            }
        }
        Console.WriteLine($"Environment:  {env}");
        Console.WriteLine($"Scripts root: {scriptsRoot}");
        Console.WriteLine($"Scripts:      {realScripts.Count}");
        if (noSeed)
            Console.WriteLine("Seed data:    SKIPPED (--no-seed)");
        else if (noDemo)
            Console.WriteLine("Demo parties: SKIPPED (--no-demo)");
        Console.WriteLine();

        var builder = new SqlConnectionStringBuilder(cs);
        Console.WriteLine($"Target server:   {builder.DataSource}");
        Console.WriteLine($"Target database: {builder.InitialCatalog}");
        Console.WriteLine();

        var failed = 0;

        foreach (var script in realScripts)
        {
            var relative = Path.GetRelativePath(scriptsRoot, script);
            Console.Write($"  Running {relative}...");

            // First script creates the database — must connect to master
            var database = Path.GetFileName(script).StartsWith("000_")
                ? "master"
                : builder.InitialCatalog;

            var (exitCode, stderr) = RunSqlCmd(
                sqlcmd,
                script,
                builder.DataSource,
                builder.IntegratedSecurity,
                builder.TrustServerCertificate,
                database);

            if (exitCode == 0)
            {
                Console.WriteLine(" OK");
            }
            else
            {
                Console.WriteLine($" FAILED");
                if (!string.IsNullOrWhiteSpace(stderr))
                    Console.WriteLine($"    {stderr.Trim()}");
                failed++;
            }
        }

        Console.WriteLine();

        if (failed > 0)
        {
            Console.WriteLine($"Reset completed with {failed} failure(s).");
            return 1;
        }

        Console.WriteLine("Reset complete.");
        return 0;
    }

    private static List<string> CollectScripts(string scriptsRoot)
    {
        var result = new List<string>();

        result.AddRange(Directory
            .GetFiles(scriptsRoot, "*.sql", SearchOption.TopDirectoryOnly)
            .OrderBy(f => f));

        foreach (var dir in Directory.GetDirectories(scriptsRoot).OrderBy(d => d))
        {
            result.AddRange(Directory
                .GetFiles(dir, "*.sql", SearchOption.TopDirectoryOnly)
                .OrderBy(f => f));
        }

        return result;
    }

    internal static string? FindSqlCmdPublic() => FindSqlCmd();

    private static string? FindSqlCmd()
    {
        // Check PATH first
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            var candidate = Path.Combine(dir, "sqlcmd.exe");
            if (File.Exists(candidate)) return candidate;
        }

        // Common install locations on Windows
        var commonPaths = new[]
        {
            @"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
            @"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\160\Tools\Binn\sqlcmd.exe",
            @"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\150\Tools\Binn\sqlcmd.exe",
        };

        return commonPaths.FirstOrDefault(File.Exists);
    }

    private static (int exitCode, string stderr) RunSqlCmd(
        string sqlcmd,
        string scriptPath,
        string server,
        bool   trustedConnection,
        bool   trustServerCert  = false,
        string database         = "master")
    {
        var authPart = trustedConnection ? "-E" : "";
        var certPart = trustServerCert   ? "-C" : "";
        var dbPart   = $"-d \"{database}\"";

        var args = $"-S \"{server}\" {dbPart} {authPart} {certPart} -i \"{scriptPath}\" -b"
            .Replace("  ", " ").Trim();

        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName               = sqlcmd,
            Arguments              = args,
            RedirectStandardError  = true,
            RedirectStandardOutput = false,
            UseShellExecute        = false
        };

        using var process = System.Diagnostics.Process.Start(psi)!;
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();

        return (process.ExitCode, stderr);
    }
}
