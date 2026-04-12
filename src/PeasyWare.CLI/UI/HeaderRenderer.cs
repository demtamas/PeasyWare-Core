using PeasyWare.Infrastructure.Settings;

namespace PeasyWare.CLI.UI;

public static class HeaderRenderer
{
    public static void Render(
        RuntimeSettings settings,
        bool diagnosticsEnabled,
        Guid? sessionId = null)
    {
        Console.Clear();

        Console.WriteLine("PeasyWare CLI");
        Console.WriteLine("Warehouse Management System");

        if (diagnosticsEnabled)
        {
            Console.WriteLine(
                $"Environment: {settings.Environment.ToUpper()}   [DIAGNOSTIC MODE]");
            Console.WriteLine("──────────────────────────────────");
        }
        else
        {
            Console.WriteLine($"Environment: {settings.Environment.ToUpper()}");
            Console.WriteLine("───────────────────────────");
        }

        Console.WriteLine();

        if (diagnosticsEnabled)
        {
            Console.WriteLine("[diag]");
            //Console.WriteLine($"Correlation ID : {CorrelationContext.Current}");

            if (sessionId.HasValue)
                Console.WriteLine($"Session ID     : {sessionId}");

            Console.WriteLine("──────────────────────────────────");
            Console.WriteLine();
        }
    }
}
