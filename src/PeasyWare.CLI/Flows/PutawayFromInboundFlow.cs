using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Scanning;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Threading;

namespace PeasyWare.CLI.Flows
{
    public class PutawayFromInboundFlow
    {
        private readonly AppRuntime     _runtime;
        private readonly SessionContext _session;

        public PutawayFromInboundFlow(AppRuntime runtime, SessionContext session)
        {
            _runtime = runtime;
            _session = session;
        }

        public void Run()
        {
            var queryRepo   = _runtime.Repositories.CreateInventoryQuery(_session);
            var commandRepo = _runtime.Repositories.CreateWarehouseTaskCommand(_session);

            while (true)
            {
                Console.Clear();
                Console.WriteLine("──────────────────────────");
                Console.WriteLine("Putaway from inbound");
                Console.WriteLine("──────────────────────────");

                if (_session.UiMode >= UiMode.Standard)
                {
                    var awaiting = queryRepo.GetUnitsAwaitingPutawayCount();
                    Console.WriteLine($"Pallets awaiting putaway: {awaiting}");
                    Console.WriteLine();
                }

                // ------------------------------------------------
                // Step 1 — Pallet scan
                // Accepts GS1-128 pallet label or plain SSCC string.
                // ------------------------------------------------
                Console.Write("Scan pallet SSCC (0=exit): ");
                var rawSscc = Console.ReadLine()?.Trim();

                if (string.IsNullOrWhiteSpace(rawSscc) || rawSscc == "0")
                    return;

                var ssccScan = GtinParser.Parse(rawSscc);

                string sscc;

                if (ssccScan.IsValid && ssccScan.Sscc is not null)
                {
                    sscc = ssccScan.Sscc;

                    if (_session.UiMode == UiMode.Trace)
                    {
                        Console.WriteLine($"[SCAN] IsPallet={ssccScan.IsPalletScan}  SSCC={sscc}");
                        if (ssccScan.BestBefore is not null)
                            Console.WriteLine($"[SCAN] BBE: {ssccScan.BestBefore:dd-MM-yyyy}");
                    }
                }
                else
                {
                    // Plain Code-128 SSCC label or manual entry — use as-is
                    sscc = rawSscc;

                    if (_session.UiMode == UiMode.Trace)
                        Console.WriteLine($"[SCAN] No GS1 SSCC — using raw: '{sscc}'");
                }

                try
                {
                    var unit = queryRepo.GetInventoryUnitByExternalRef(sscc);

                    if (unit == null)
                    {
                        Console.WriteLine("Inventory unit not recognised.");
                        Console.ReadKey(true);
                        continue;
                    }

                    var result = commandRepo.CreatePutawayTask(unit.InventoryUnitId);

                    if (!result.Success)
                    {
                        Console.WriteLine(result.FriendlyMessage);
                        Console.ReadKey(true);
                        continue;
                    }

                    Console.WriteLine();
                    Console.WriteLine("────────────────────────────────────────────");
                    Console.WriteLine("PUTAWAY TASK CREATED");
                    Console.WriteLine($"Pallet  : {sscc}");
                    Console.WriteLine($"Task ID : {result.TaskId}");
                    Console.WriteLine($"Bin     : {result.DestinationBinCode}");

                    if (_session.UiMode >= UiMode.Standard)
                    {
                        Console.WriteLine();
                        Console.WriteLine("---- DETAILS ----");
                        Console.WriteLine($"Source Bin   : {result.SourceBinCode}");
                        Console.WriteLine($"Stock State  : {result.StockStateCode}");
                        Console.WriteLine($"Stock Status : {result.StockStatusCode}");
                    }

                    if (_session.UiMode == UiMode.Trace)
                    {
                        Console.WriteLine();
                        Console.WriteLine("---- TRACE ----");
                        Console.WriteLine($"Unit ID      : {result.InventoryUnitId}");
                        Console.WriteLine($"Zone         : {result.ZoneCode ?? "N/A"}");
                        if (result.ExpiresAt.HasValue)
                            Console.WriteLine($"Task Expires : {result.ExpiresAt.Value:HH:mm:ss} UTC");
                    }

                    Console.WriteLine("────────────────────────────────────────────");
                    Console.WriteLine();

                    // ------------------------------------------------
                    // Step 2 — Destination bin scan
                    //
                    // Bin labels are virtually always plain Code-128 with
                    // the bin code as the raw value (e.g. "R0201B").
                    // Some sites encode the bin code inside an SSCC-18
                    // (AI 00) — if so, the parsed SSCC value is used.
                    // GTIN is not a valid bin identifier and is not used.
                    // ------------------------------------------------
                    while (true)
                    {
                        Console.Write($"Scan destination bin [{result.DestinationBinCode}] (C=cancel): ");
                        var rawBin = Console.ReadLine()?.Trim();

                        if (string.IsNullOrWhiteSpace(rawBin))
                            continue;

                        if (rawBin.Equals("C", StringComparison.OrdinalIgnoreCase))
                        {
                            Console.WriteLine("Putaway cancelled.");
                            Thread.Sleep(1500);
                            break;
                        }

                        // Resolve bin code: SSCC-encoded label or plain Code-128
                        var binScan = GtinParser.Parse(rawBin);

                        var resolvedBin = binScan.IsValid && binScan.Sscc is not null
                            ? binScan.Sscc   // SSCC-encoded bin label (uncommon)
                            : rawBin;        // Plain Code-128 bin label (standard)

                        if (_session.UiMode == UiMode.Trace)
                            Console.WriteLine($"[SCAN] Bin resolved: '{resolvedBin}'");

                        if (!string.Equals(resolvedBin, result.DestinationBinCode,
                            StringComparison.OrdinalIgnoreCase))
                        {
                            Console.WriteLine($"Wrong location. Expected: {result.DestinationBinCode}");
                            continue;
                        }

                        var confirmResult = commandRepo.ConfirmPutawayTask(
                            result.TaskId,
                            resolvedBin);

                        Console.WriteLine(confirmResult.FriendlyMessage);

                        if (confirmResult.Success)
                            Thread.Sleep(1000);
                        else
                            Console.ReadKey(true);

                        break;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Putaway failed: {ex.Message}");
                    if (_session.UiMode == UiMode.Trace)
                        Console.WriteLine($"[TRACE] {ex}");
                    Console.ReadKey(true);
                }
            }
        }
    }
}
