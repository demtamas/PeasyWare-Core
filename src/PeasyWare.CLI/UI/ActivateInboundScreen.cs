using PeasyWare.Application.Dto;

namespace PeasyWare.CLI.UI;

public static class ActivateInboundScreen
{
    public static string PromptInboundRef(IEnumerable<ActivatableInboundDto> activatable)
    {
        Console.WriteLine();
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("Activate Inbound");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("Enter inbound ref to activate.");
        Console.WriteLine("Type 'L' to list activatable inbounds.");
        Console.WriteLine("Type '0' to go back.");
        Console.WriteLine();

        while (true)
        {
            Console.Write("Inbound ref / L / 0: ");
            var input = (Console.ReadLine() ?? "").Trim();

            if (input == "0") return "";
            if (input.Equals("L", StringComparison.OrdinalIgnoreCase))
            {
                RenderList(activatable);
                continue;
            }

            if (!string.IsNullOrWhiteSpace(input))
                return input;

            Console.WriteLine("Please enter a ref, 'L' to list, or '0' to go back.");
        }
    }

    private static void RenderList(IEnumerable<ActivatableInboundDto> data)
    {
        var list = data.ToList();
        Console.WriteLine();

        if (list.Count == 0)
        {
            Console.WriteLine("No activatable inbounds found (EXPECTED with EXPECTED lines).");
            Console.WriteLine();
            return;
        }

        Console.WriteLine("Activatable inbounds:");
        Console.WriteLine("------------------------------------------------------------");
        for (var i = 0; i < list.Count; i++)
        {
            var d = list[i];
            var eta = d.ExpectedArrivalAt?.ToString("yyyy-MM-dd HH:mm") ?? "-";
            Console.WriteLine($"{i + 1,2}. {d.InboundRef,-20} ETA: {eta,-16} Lines: {d.LineCount}");
        }
        Console.WriteLine("------------------------------------------------------------");
        Console.WriteLine("Tip: copy/paste the ref above into the prompt.");
        Console.WriteLine();
    }
}
