using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Scanning;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Threading;

namespace PeasyWare.CLI.Flows;

/// <summary>
/// Bin-to-bin movement flow.
///
/// Use cases:
///   - Putaway fallback: no suitable location found by the system, operator
///     knows where it can go (bulk bin, maintenance area, overflow bay)
///   - Consolidation: merge partial pallets or fill a zone before a bay empties
///   - High-bay section clear: maintenance requires a zone to be emptied
///   - General relocation: supervisor decision to move stock
///
/// Flow:
///   1. Scan SSCC → validate the unit is free to move (state, status, no
///      other open task) and the destination bin can take it, then create
///      the MOVE task and reserve the destination bin
///   2. Operator enters destination bin, or presses S to request a suggestion
///   3. Scan destination bin to confirm → rules re-checked under lock,
///      then write placement + movement log
///
/// A move task does not change the unit's stock state. While it is open
/// (one open task per unit) the unit cannot be picked, put away or moved
/// again, and the destination bin is held by a reservation. Both lapse
/// after the task TTL; starting a new move for an expired task replaces it.
/// Cancelling at the confirm step releases both immediately.
/// </summary>
public sealed class BinToBinMoveFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public BinToBinMoveFlow(AppRuntime runtime, SessionContext session)
    {
        _runtime = runtime;
        _session = session;
    }

    public void Run()
    {
        var commandRepo = _runtime.Repositories.CreateWarehouseTaskCommand(_session);

        while (true)
        {
            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Bin-to-bin movement");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();

            // ------------------------------------------------
            // Step 1 — Scan SSCC
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
                    Console.WriteLine($"[SCAN] SSCC={sscc}");
            }
            else
            {
                sscc = rawSscc;

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[SCAN] No GS1 SSCC — using raw: '{sscc}'");
            }

            // ------------------------------------------------
            // Step 2 — Destination bin
            // Default: operator types/scans destination
            // S key:   request system suggestion
            // ------------------------------------------------
            Console.WriteLine();
            Console.Write("Destination bin (S=suggest, 0=cancel): ");
            var destRaw = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(destRaw) || destRaw == "0")
                continue;

            string? destinationBinCode;

            if (string.Equals(destRaw, "S", StringComparison.OrdinalIgnoreCase))
            {
                destinationBinCode = null;

                if (_session.UiMode >= UiMode.Standard)
                    Console.WriteLine("Requesting suggestion...");
            }
            else
            {
                var binScan = GtinParser.Parse(destRaw);

                destinationBinCode = binScan.IsValid && binScan.Sscc is not null
                    ? binScan.Sscc
                    : destRaw.Trim();

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[SCAN] Destination bin: '{destinationBinCode}'");
            }

            // ------------------------------------------------
            // Create task — validates move rules, reserves the destination bin
            // ------------------------------------------------
            var createResult = commandRepo.CreateBinMoveTask(sscc, destinationBinCode);

            if (!createResult.Success)
            {
                Console.WriteLine(createResult.FriendlyMessage);
                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[TRACE] ResultCode: {createResult.ResultCode}");
                Console.ReadKey(true);
                continue;
            }

            Console.WriteLine();
            Console.WriteLine("────────────────────────────────────────────");
            Console.WriteLine("MOVEMENT TASK CREATED");
            Console.WriteLine($"Pallet  : {sscc}");
            Console.WriteLine($"From    : {createResult.SourceBinCode}");
            Console.WriteLine($"To      : {createResult.DestinationBinCode}");

            if (_session.UiMode >= UiMode.Standard)
                Console.WriteLine($"Task ID : {createResult.TaskId}");

            if (_session.UiMode == UiMode.Trace)
                Console.WriteLine($"Unit ID : {createResult.InventoryUnitId}");

            Console.WriteLine("────────────────────────────────────────────");
            Console.WriteLine();

            // ------------------------------------------------
            // Step 3 — Scan destination bin to confirm
            // ------------------------------------------------
            while (true)
            {
                Console.Write($"Scan destination bin [{createResult.DestinationBinCode}] to confirm (C=cancel): ");
                var confirmRaw = Console.ReadLine()?.Trim();

                if (string.IsNullOrWhiteSpace(confirmRaw))
                    continue;

                if (confirmRaw.Equals("C", StringComparison.OrdinalIgnoreCase))
                {
                    var cancelResult = commandRepo.CancelTask(
                        createResult.TaskId, "Cancelled by operator at confirmation");

                    Console.WriteLine(cancelResult.Success
                        ? "Movement cancelled. The pallet stays where it is."
                        : cancelResult.FriendlyMessage);

                    Thread.Sleep(1500);
                    break;
                }

                var confirmBinScan = GtinParser.Parse(confirmRaw);

                var resolvedBin = confirmBinScan.IsValid && confirmBinScan.Sscc is not null
                    ? confirmBinScan.Sscc
                    : confirmRaw;

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[SCAN] Confirm bin: '{resolvedBin}'");

                var confirmResult = commandRepo.ConfirmBinMoveTask(
                    createResult.TaskId,
                    resolvedBin);

                var message = confirmResult.FriendlyMessage;

                Console.WriteLine(message);

                if (_session.UiMode == UiMode.Trace && !confirmResult.Success)
                    Console.WriteLine($"[TRACE] ResultCode: {confirmResult.ResultCode}");

                if (confirmResult.Success)
                {
                    Thread.Sleep(1000);
                    break;
                }

                Console.ReadKey(true);
            }
        }
    }
}
