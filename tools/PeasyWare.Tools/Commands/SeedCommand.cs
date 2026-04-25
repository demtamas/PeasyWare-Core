namespace PeasyWare.Tools.Commands;

/// <summary>
/// Runs seed scripts from Database/Scripts/seed/ against the current DB.
/// All seed scripts are idempotent — safe to run on an existing DB.
///
/// Usage:
///   pwtools seed                    — runs all scripts in Scripts/seed/
///   pwtools seed 901_test_data      — runs a specific seed file
/// </summary>
internal static class SeedCommand
{
    public static int Run(string[] args)
    {
        string scriptsRoot;

        try { scriptsRoot = ToolsConfig.GetScriptsRoot(); }
        catch (Exception ex) { Console.WriteLine($"ERROR: {ex.Message}"); return 1; }

        var seedRoot = Path.Combine(scriptsRoot, "seed");

        if (!Directory.Exists(seedRoot))
        {
            Console.WriteLine($"ERROR: Seed directory not found: {seedRoot}");
            return 1;
        }

        // Specific file requested?
        var filter = args.Length > 1 ? args[1] : null;

        var scripts = Directory
            .GetFiles(seedRoot, "*.sql")
            .OrderBy(f => f)
            .Where(f => filter is null ||
                        Path.GetFileNameWithoutExtension(f).Contains(filter, StringComparison.OrdinalIgnoreCase))
            .ToList();

        if (scripts.Count == 0)
        {
            Console.WriteLine(filter is null
                ? "No seed scripts found."
                : $"No seed scripts matching '{filter}'.");
            return 1;
        }

        var sqlcmd = ResetDbCommand.FindSqlCmdPublic();
        if (sqlcmd is null)
        {
            Console.WriteLine("ERROR: sqlcmd not found on PATH.");
            return 1;
        }

        var cs      = ToolsConfig.GetConnectionString();
        var builder = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(cs);

        Console.WriteLine($"Seeding {scripts.Count} script(s) against {builder.InitialCatalog}...");
        Console.WriteLine();

        var failed = 0;

        foreach (var script in scripts)
        {
            var relative = Path.GetFileName(script);
            Console.Write($"  {relative}...");

            var (exit, stderr) = RunScript(sqlcmd, script, builder.DataSource, builder.IntegratedSecurity);

            if (exit == 0)
                Console.WriteLine(" OK");
            else
            {
                Console.WriteLine(" FAILED");
                if (!string.IsNullOrWhiteSpace(stderr))
                    Console.WriteLine($"    {stderr.Trim()}");
                failed++;
            }
        }

        Console.WriteLine();
        Console.WriteLine(failed > 0 ? $"Seed completed with {failed} failure(s)." : "Seed complete.");
        return failed > 0 ? 1 : 0;
    }

    private static (int, string) RunScript(string sqlcmd, string path, string server, bool trusted)
    {
        var args = trusted
            ? $"-S \"{server}\" -E -i \"{path}\" -b"
            : $"-S \"{server}\" -i \"{path}\" -b";

        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName               = sqlcmd,
            Arguments              = args,
            RedirectStandardError  = true,
            UseShellExecute        = false
        };

        using var p = System.Diagnostics.Process.Start(psi)!;
        var stderr  = p.StandardError.ReadToEnd();
        p.WaitForExit();

        return (p.ExitCode, stderr);
    }
}
