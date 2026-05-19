using PeasyWare.Application.Dto;

namespace PeasyWare.CLI.UI;

public static class ActivateInboundScreen
{
    public static string PromptInboundRef(IEnumerable<ActivatableInboundDto> activatable)
    {
        var list = activatable.ToList();

        Console.WriteLine();
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("Activate Inbound");
        Console.WriteLine("──────────────────────────");

        // Always show the list upfront if there's anything to show
        if (list.Count > 0)
            RenderList(list);
        else
            Console.WriteLine("No activatable inbounds found.");

        Console.WriteLine("Type a number to select, ref to activate, or 0 to go back.");
        Console.WriteLine();

        while (true)
        {
            Console.Write("# / Inbound ref / 0: ");
            var input = (Console.ReadLine() ?? "").Trim();

            if (input == "0") return "";

            // Numeric selection from list
            if (int.TryParse(input, out var idx) && idx >= 1 && idx <= list.Count)
                return list[idx - 1].InboundRef;

            if (!string.IsNullOrWhiteSpace(input))
                return input;

            Console.WriteLine($"Enter a number (1-{list.Count}), a ref, or 0 to go back.");
        }
    }

    private static void RenderList(IEnumerable<ActivatableInboundDto> data)
    {
        var list = data.ToList();
        Console.WriteLine();
        Console.WriteLine("------------------------------------------------------------");
        for (var i = 0; i < list.Count; i++)
        {
            var d   = list[i];
            var eta = d.ExpectedArrivalAt?.ToString("yyyy-MM-dd HH:mm") ?? "-";
            Console.WriteLine($"{i + 1,2}. {d.InboundRef,-20} ETA: {eta,-16} Lines: {d.LineCount}");
        }
        Console.WriteLine("------------------------------------------------------------");
        Console.WriteLine();
    }
}
