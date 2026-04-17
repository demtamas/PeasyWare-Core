using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Scanning;
using PeasyWare.Infrastructure.Bootstrap;
using System;

namespace PeasyWare.CLI.Flows;

/// <summary>
/// SSCC stock enquiry flow.
///
/// Operator scans a pallet SSCC and sees its current state.
/// UiMode controls detail level:
///
///   Minimal  — SSCC, SKU, bin, state, status
///   Standard — + batch, BBE, quantity, zone, storage type,
///                received at/by, last movement type
///   Trace    — + last movement timestamp and last moved by
/// </summary>
public sealed class SsccQueryFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public SsccQueryFlow(AppRuntime runtime, SessionContext session)
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
            Console.WriteLine("Stock enquiry — SSCC");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();
            Console.Write("Scan pallet SSCC (0=exit): ");

            var rawInput = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(rawInput) || rawInput == "0")
                return;

            // Resolve SSCC from GS1-128 label or plain string
            var scan = GtinParser.Parse(rawInput);

            var sscc = scan.IsValid && scan.Sscc is not null
                ? scan.Sscc
                : rawInput;

            var stock = queryRepo.GetActiveInventoryBySscc(sscc);

            Console.WriteLine();

            if (stock is null)
            {
                // Check whether the pallet exists but is in a terminal state —
                // shipped pallets sometimes get scanned in error
                Console.WriteLine("Pallet not found in active inventory.");
                Console.WriteLine("It may have been shipped, reversed, or never received.");
                Console.WriteLine();
                Console.WriteLine("Press any key to scan again.");
                Console.ReadKey(true);
                continue;
            }

            RenderResult(stock);

            Console.WriteLine();
            Console.WriteLine("Press any key to scan again.");
            Console.ReadKey(true);
        }
    }

    private void RenderResult(ActiveInventoryDto s)
    {
        Console.WriteLine("────────────────────────────────────────────────────────────");

        // ── MINIMAL — always shown ───────────────────────────────────────
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

        // ── STANDARD — operational detail ────────────────────────────────
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

        // ── TRACE — full audit detail ─────────────────────────────────────
        Console.WriteLine();
        Console.WriteLine("---- TRACE ----");
        if (s.LastMovementAt.HasValue)
            Console.WriteLine($"Last move at: {s.LastMovementAt.Value:dd-MM-yyyy HH:mm:ss}  by {s.LastMovedBy ?? "unknown"}");
        else
            Console.WriteLine("Last move at: (no movement recorded)");

        Console.WriteLine("────────────────────────────────────────────────────────────");
    }
}
