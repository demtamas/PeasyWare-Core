namespace PeasyWare.Tools.Commands;

/// <summary>
/// Runs the PeasyWare test suite via dotnet test.
/// Formats output for readability and prints a clean summary.
///
/// Usage:
///   pwtools test                    — run all tests
///   pwtools test --filter Login     — run tests matching filter
/// </summary>
internal static class TestCommand
{
    public static int Run(string[] args)
    {
        string solutionRoot;

        try
        {
            // Walk up to find solution root
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null && dir.GetFiles("PeasyWare.sln").Length == 0)
                dir = dir.Parent;

            if (dir is null)
            {
                Console.WriteLine("ERROR: Could not locate PeasyWare.sln.");
                return 1;
            }

            solutionRoot = dir.FullName;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR: {ex.Message}");
            return 1;
        }

        var slnPath = Path.Combine(solutionRoot, "PeasyWare.sln");

        // Build dotnet test arguments
        var filterIndex = Array.IndexOf(args, "--filter");
        var filter      = filterIndex >= 0 && filterIndex + 1 < args.Length
            ? args[filterIndex + 1]
            : null;

        var dotnetArgs = filter is not null
            ? $"test \"{slnPath}\" --filter \"{filter}\" --logger console;verbosity=minimal"
            : $"test \"{slnPath}\" --logger console;verbosity=minimal";

        Console.WriteLine("PeasyWare Test Runner");
        Console.WriteLine(new string('─', 60));
        if (filter is not null)
            Console.WriteLine($"Filter: {filter}");
        Console.WriteLine();

        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName               = "dotnet",
            Arguments              = dotnetArgs,
            UseShellExecute        = false,
            RedirectStandardOutput = false,
            RedirectStandardError  = false,
            WorkingDirectory       = solutionRoot
        };

        using var process = System.Diagnostics.Process.Start(psi)!;
        process.WaitForExit();

        Console.WriteLine();
        Console.WriteLine(process.ExitCode == 0
            ? "All tests passed."
            : "One or more tests failed.");

        return process.ExitCode;
    }
}
