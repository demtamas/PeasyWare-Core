using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Collections.Generic;

namespace PeasyWare.CLI.Flows;

/// <summary>
/// Bin stock enquiry flow.
///
/// Single unit  → full detail rendered immediately
/// Multiple units → summary table, D to drill into detail,
///                  N/P to iterate, B to return to summary
///
/// UiMode applies to the detail view:
///   Minimal  — SSCC, SKU, state, status
///   Standard — + quantity, batch, BBE, zone, storage, received at/by, last move
///   Trace    — + exact last move timestamp and last moved by
/// </summary>
public sealed class BinQueryFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public BinQueryFlow(AppRuntime runtime, SessionContext session)
    {
        _runtime = runtime;
        _session = session;
    }

    public void Run()
    {
        var queryRepo = _runtime.Repositories.CreateInventoryQuery(_session);

        while (true)
        {
            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Stock enquiry — Bin");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();
            Console.Write("Scan or enter bin code (0=exit): ");

            var rawInput = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(rawInput) || rawInput == "0")
                return;

            var binCode = rawInput.ToUpperInvariant();

            var units = queryRepo.GetActiveInventoryByBin(binCode);

            Console.WriteLine();

            if (units.Count == 0)
            {
                // Distinguish between a known empty bin and a bin that doesn't exist
                if (queryRepo.BinExists(binCode))
                    Console.WriteLine($"Bin {binCode} is empty.");
                else
                    Console.WriteLine($"Bin {binCode} does not exist.");

                Console.WriteLine();
                Console.WriteLine("Press any key to scan again.");
                Console.ReadKey(true);
                continue;
            }

            if (units.Count == 1)
            {
                RenderBinHeader(binCode, units);
                RenderDetail(units[0]);
                Console.WriteLine();
                Console.WriteLine("Press any key to scan again.");
                Console.ReadKey(true);
            }
            else
            {
                RunMultiUnitView(binCode, units);
            }
        }
    }

    // --------------------------------------------------
    // Multi-unit view
    // --------------------------------------------------

    private void RunMultiUnitView(string binCode, IReadOnlyList<ActiveInventoryDto> units)
    {
        while (true)
        {
            RenderSummary(binCode, units);

            Console.WriteLine();
            Console.Write("D=detail  0=back: ");
            var key = Console.ReadLine()?.Trim();

            if (key == "0" || string.IsNullOrWhiteSpace(key))
                return;

            if (!string.Equals(key, "D", StringComparison.OrdinalIgnoreCase))
                continue;

            RunDetailNavigation(binCode, units);
        }
    }

    // --------------------------------------------------
    // Detail navigation
    // --------------------------------------------------

    private void RunDetailNavigation(string binCode, IReadOnlyList<ActiveInventoryDto> units)
    {
        var index = 0;

        while (true)
        {
            Console.Clear();
            Console.WriteLine($"Bin {binCode}  —  {index + 1} of {units.Count}");
            Console.WriteLine("────────────────────────────────────────────────────────────");
            RenderDetail(units[index]);
            Console.WriteLine();
            Console.Write("N=next  P=prev  B=back to summary: ");

            var key = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(key))
                continue;

            if (string.Equals(key, "B", StringComparison.OrdinalIgnoreCase))
                return;

            if (string.Equals(key, "N", StringComparison.OrdinalIgnoreCase))
            {
                if (index < units.Count - 1)
                    index++;
                else
                    Console.WriteLine("Already at last unit.");
                continue;
            }

            if (string.Equals(key, "P", StringComparison.OrdinalIgnoreCase))
            {
                if (index > 0)
                    index--;
                else
                    Console.WriteLine("Already at first unit.");
                continue;
            }
        }
    }

    // --------------------------------------------------
    // Renderers
    // --------------------------------------------------

    private static void RenderBinHeader(string binCode, IReadOnlyList<ActiveInventoryDto> units)
    {
        var first = units[0];
        Console.WriteLine("────────────────────────────────────────────────────────────");
        Console.WriteLine($"Bin:          {binCode}");
        Console.WriteLine($"Zone:         {first.ZoneCode ?? "Staging"}");
        Console.WriteLine($"Storage:      {first.StorageTypeCode ?? "(none)"}");
        Console.WriteLine($"Units:        {units.Count}");
        Console.WriteLine("────────────────────────────────────────────────────────────");
    }

    private void RenderSummary(string binCode, IReadOnlyList<ActiveInventoryDto> units)
    {
        Console.Clear();
        RenderBinHeader(binCode, units);
        Console.WriteLine();

        Console.WriteLine($"  {"#",-3} {"SSCC",-22} {"SKU",-10} {"Qty",5}  {"State",-12} {"Status"}");
        Console.WriteLine($"  {new string('-', 70)}");

        for (int i = 0; i < units.Count; i++)
        {
            var u = units[i];
            Console.WriteLine(
                $"  {i + 1,-3} {u.Sscc,-22} {u.SkuCode,-10} {u.Quantity,5}  {u.StockState,-12} {u.StockStatus}");
        }

        if (_session.UiMode >= UiMode.Standard)
        {
            Console.WriteLine();
            Console.WriteLine("  ---- Totals by SKU ----");

            var grouped = new Dictionary<string, (int qty, string desc)>();
            foreach (var u in units)
            {
                if (grouped.TryGetValue(u.SkuCode, out var existing))
                    grouped[u.SkuCode] = (existing.qty + u.Quantity, existing.desc);
                else
                    grouped[u.SkuCode] = (u.Quantity, u.SkuDescription);
            }

            foreach (var (sku, (qty, desc)) in grouped)
                Console.WriteLine($"  {sku,-10} {desc,-30} {qty,6} units");
        }
    }

    private void RenderDetail(ActiveInventoryDto s)
    {
        Console.WriteLine($"SSCC:         {s.Sscc}");
        Console.WriteLine($"SKU:          {s.SkuCode}  {s.SkuDescription}");
        Console.WriteLine($"Location:     {s.BinCode}");
        Console.WriteLine($"State:        {s.StockState}");
        Console.WriteLine($"Status:       {s.StockStatus}");

        if (_session.UiMode < UiMode.Standard)
        {
            Console.WriteLine("────────────────────────────────────────────────────────────");
            return;
        }

        Console.WriteLine();
        Console.WriteLine($"Quantity:     {s.Quantity}");
        Console.WriteLine($"Batch:        {s.BatchNumber ?? "(none)"}");
        Console.WriteLine($"BBE:          {(s.BestBeforeDate.HasValue ? s.BestBeforeDate.Value.ToString("dd-MM-yyyy") : "(none)")}");
        Console.WriteLine($"Zone:         {s.ZoneCode ?? "Staging"}");
        Console.WriteLine($"Storage:      {s.StorageTypeCode ?? "(none)"}");
        Console.WriteLine();
        Console.WriteLine($"Received:     {s.ReceivedAt:dd-MM-yyyy HH:mm}  by {s.ReceivedBy ?? "unknown"}");
        Console.WriteLine($"Last move:    {s.LastMovementType ?? "(none)"}");

        if (_session.UiMode < UiMode.Trace)
        {
            Console.WriteLine("────────────────────────────────────────────────────────────");
            return;
        }

        Console.WriteLine();
        Console.WriteLine("---- TRACE ----");
        if (s.LastMovementAt.HasValue)
            Console.WriteLine($"Last move at: {s.LastMovementAt.Value:dd-MM-yyyy HH:mm:ss}  by {s.LastMovedBy ?? "unknown"}");
        else
            Console.WriteLine("Last move at: (no movement recorded)");

        Console.WriteLine("────────────────────────────────────────────────────────────");
    }
}
