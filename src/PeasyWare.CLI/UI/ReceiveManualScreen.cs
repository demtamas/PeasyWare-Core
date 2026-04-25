using PeasyWare.Application;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Scanning;
using System;

namespace PeasyWare.CLI.UI;

public static class ReceiveManualScreen
{
    // ------------------------------------------------------------
    // Scan-driven receive preview
    // ------------------------------------------------------------

    public static void RenderScanPreview(
        InboundLineByEanDto line,
        string? sscc,
        string? batch,
        DateOnly? bbe,
        string bin,
        UiMode uiMode)
    {
        Console.WriteLine();
        Console.WriteLine("────────────────────────────────────────────────────────────");
        Console.WriteLine($"SKU:         {line.SkuCode} | {line.SkuDescription}");
        Console.WriteLine($"EAN:         {line.Ean}");
        Console.WriteLine($"SSCC:        {sscc ?? "(not yet scanned)"}");
        Console.WriteLine($"Batch:       {batch ?? "(none)"}");
        Console.WriteLine($"BBE:         {(bbe.HasValue ? bbe.Value.ToString("dd-MM-yyyy") : "(none)")}");
        Console.WriteLine($"Bin:         {bin}");
        Console.WriteLine($"Stock Status:{line.ArrivalStockStatusCode}");

        if (uiMode >= UiMode.Standard)
        {
            Console.WriteLine();
            Console.WriteLine("---- DETAILS ----");
            Console.WriteLine($"Outstanding: {line.OutstandingQty} / {line.ExpectedQty}");
            Console.WriteLine($"Batch req'd: {(line.IsBatchRequired ? "Yes" : "No")}");
            Console.WriteLine($"Std HU qty:  {(line.StandardHuQuantity.HasValue ? line.StandardHuQuantity.Value.ToString() : "(not set)")}");
        }

        if (uiMode == UiMode.Trace)
        {
            Console.WriteLine();
            Console.WriteLine("---- TRACE ----");
            Console.WriteLine($"Line ID:     {line.InboundLineId}");
            Console.WriteLine($"Matched by:  {line.MatchedBy}");
        }

        Console.WriteLine("────────────────────────────────────────────────────────────");
    }

    // ------------------------------------------------------------
    // Quantity — used when StandardHuQuantity is NULL (no default known)
    // Goes straight to number entry.
    // ------------------------------------------------------------

    public static int PromptQuantityWithDefault(int? defaultQty, int max)
    {
        // No default — straight to number entry
        if (!defaultQty.HasValue)
            return PromptQuantityEntry(max);

        // Has default — single keypress: any key accepts, C changes, 0 back
        Console.Write($"Quantity: {defaultQty.Value}  — C=change  0=back  any key=accept: ");
        var key = Console.ReadKey(intercept: true);
        Console.WriteLine();

        if (key.KeyChar == '0') return 0;
        if (key.KeyChar == 'C' || key.KeyChar == 'c') return PromptQuantityEntry(max);

        return defaultQty.Value;
    }

    // ------------------------------------------------------------
    // Quantity change — called from Q at confirmation.
    // Goes straight to number entry, no intermediate keypress step.
    // ------------------------------------------------------------

    public static int PromptQuantityChange(int max)
        => PromptQuantityEntry(max);

    // ------------------------------------------------------------
    // Internal: number entry loop
    // ------------------------------------------------------------

    private static int PromptQuantityEntry(int max)
    {
        while (true)
        {
            Console.Write($"Enter quantity (1-{max}, 0=back): ");
            var input = Console.ReadLine()?.Trim();

            if (int.TryParse(input, out var qty))
            {
                if (qty == 0) return 0;
                if (qty >= 1 && qty <= max) return qty;
            }

            Console.WriteLine($"Enter a number between 1 and {max}.");
        }
    }

    // ------------------------------------------------------------
    // Batch prompt
    // ------------------------------------------------------------

    public static string? PromptBatch(string? prefilled, bool isRequired)
    {
        if (prefilled is not null)
        {
            var normalised = IdentifierPolicy.NormaliseBatch(prefilled);
            Console.WriteLine($"Batch:       {normalised}  [from scan]");
            return normalised;
        }

        while (true)
        {
            Console.Write(isRequired
                ? "Batch number (required): "
                : "Batch number (Enter to skip): ");

            var input = Console.ReadLine()?.Trim();

            if (!string.IsNullOrWhiteSpace(input))
                return IdentifierPolicy.NormaliseBatch(input);

            if (!isRequired)
                return null;

            Console.WriteLine("Batch number is required for this SKU.");
        }
    }

    // ------------------------------------------------------------
    // BBE prompt
    // ------------------------------------------------------------

    public static DateOnly? PromptBbe(DateOnly? prefilled = null)
    {
        if (prefilled is not null)
        {
            Console.WriteLine($"BBE:         {prefilled:dd-MM-yyyy}  [from scan]");
            return prefilled;
        }

        Console.Write("Best before (dd-MM-yyyy, Enter to skip): ");
        var input = Console.ReadLine()?.Trim();

        if (!string.IsNullOrWhiteSpace(input) &&
            DateOnly.TryParseExact(input, "dd-MM-yyyy", out var parsed))
            return parsed;

        return null;
    }

    // ------------------------------------------------------------
    // Line list — kept for any future fallback / admin use
    // ------------------------------------------------------------

    public static void RenderLines(System.Collections.Generic.IReadOnlyList<InboundLineDto> lines)
    {
        Console.WriteLine();
        Console.WriteLine("Lines to receive");
        Console.WriteLine("────────────────────────────────────────────────────────────");
        Console.WriteLine($"  {"#",-4} {"SKU",-15} {"Description",-30} {"Exp",6} {"Rcv",6} {"Out",6}");
        Console.WriteLine("────────────────────────────────────────────────────────────");

        for (int i = 0; i < lines.Count; i++)
        {
            var l = lines[i];
            Console.WriteLine(
                $"  {i + 1,-4} {l.SkuCode,-15} {l.Description,-30} " +
                $"{l.ExpectedQty,6} {l.ReceivedQty,6} {l.OutstandingQty,6}");
        }

        Console.WriteLine("────────────────────────────────────────────────────────────");
    }

    public static int PromptLineSelection(int max)
    {
        while (true)
        {
            Console.Write("Select line (0=exit): ");
            var input = Console.ReadLine()?.Trim();
            if (int.TryParse(input, out var n) && n >= 0 && n <= max) return n;
            Console.WriteLine("Invalid selection.");
        }
    }

    public static bool PromptConfirm(int qty, string skuCode, string bin)
    {
        Console.Write($"Confirm receive {qty} x {skuCode} into {bin}? (YES/no): ");
        var input = Console.ReadLine()?.Trim();
        return string.Equals(input, "YES", StringComparison.Ordinal);
    }
}
