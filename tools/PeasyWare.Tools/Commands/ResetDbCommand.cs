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
/// </summary>
internal static class ResetDbCommand
{
    public static int Run(string[] args)
    {
        var confirm = args.Contains("--confirm");
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

            var (exitCode, stderr) = RunSqlCmd(sqlcmd, script, builder.DataSource, builder.IntegratedSecurity);

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
        bool trustedConnection)
    {
        var args = trustedConnection
            ? $"-S \"{server}\" -E -i \"{scriptPath}\" -b"
            : $"-S \"{server}\" -i \"{scriptPath}\" -b";

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
