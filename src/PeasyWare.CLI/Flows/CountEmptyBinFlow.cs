using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Scanning;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace PeasyWare.CLI.Flows;

/// <summary>
/// Empty-bin check.
///
/// The system lists the bins it believes are empty in a storage type; the
/// operator walks them and, for each:
///   - scans the bin label           → confirmed empty (the scan is the proof
///                                     the operator was actually there)
///   - presses F, scans bin + pallet → stock found: the system's record is
///                                     corrected where the move rules allow,
///                                     otherwise recorded for supervisor review
///
/// A count is left open when the operator exits, and resumed by starting the
/// same storage type again. It closes itself when the last bin is done, or
/// the operator can close it early (C).
///
/// UiMode applies as elsewhere: Trace adds the result codes.
/// </summary>
public sealed class CountEmptyBinFlow
{
    private const int ShowNext = 12;

    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public CountEmptyBinFlow(AppRuntime runtime, SessionContext session)
    {
        _runtime = runtime;
        _session = session;
    }

    public void Run()
    {
        var query   = _runtime.Repositories.CreateCountQuery(_session);
        var command = _runtime.Repositories.CreateCountCommand(_session);

        while (true)
        {
            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Count — Empty bins");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();

            var types = query.GetEmptyBinSummary();

            if (types.Count == 0)
            {
                Console.WriteLine("No storage type has empty bins to count.");
                Console.WriteLine();
                Console.WriteLine("Press any key to go back.");
                Console.ReadKey(true);
                return;
            }

            for (int i = 0; i < types.Count; i++)
            {
                var t = types[i];

                var detail = t.OpenCountId is null
                    ? $"{t.EmptyBins} empty bin(s)"
                    : $"count in progress — {t.OpenPendingBins ?? 0} left to check";

                Console.WriteLine($"{i + 1}. {t.StorageTypeCode,-10} {t.StorageTypeName,-24} {detail}");
            }

            Console.WriteLine("0. Back");
            Console.WriteLine();
            Console.Write("Select storage type: ");

            var input = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(input) || input == "0")
                return;

            if (!int.TryParse(input, out var choice) || choice < 1 || choice > types.Count)
            {
                Console.WriteLine("Invalid option.");
                Thread.Sleep(800);
                continue;
            }

            var selected = types[choice - 1];
            var start    = command.StartEmptyBinCount(selected.StorageTypeCode);

            if (!start.Success)
            {
                Console.WriteLine();
                Console.WriteLine(start.FriendlyMessage);
                Trace(start.ResultCode);
                Console.WriteLine("Press any key to continue.");
                Console.ReadKey(true);
                continue;
            }

            RunCount(query, command, start, selected.StorageTypeCode);
        }
    }

    // --------------------------------------------------
    // One count, bin by bin
    // --------------------------------------------------

    private void RunCount(
        ICountQueryRepository   query,
        ICountCommandRepository command,
        CountStartResult        start,
        string                  storageTypeCode)
    {
        var countId = start.CountId;

        string? lastMessage = start.Resumed
            ? $"Resumed count #{countId}."
            : $"Count #{countId} started — {start.TotalBins} bin(s) to check.";

        while (true)
        {
            var pending = query.GetPendingLines(countId);

            if (pending.Count == 0)
            {
                Complete(query, command, countId);
                return;
            }

            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine($"Count — Empty bins — {storageTypeCode}   (#{countId})");
            Console.WriteLine("──────────────────────────");

            if (lastMessage is not null)
                Console.WriteLine(lastMessage);

            Console.WriteLine();
            Console.WriteLine($"{pending.Count} bin(s) still to check. Next:");

            foreach (var line in pending.Take(ShowNext))
                Console.WriteLine($"  Zone {line.ZoneCode ?? "-",-5} {line.BinCode}");

            if (pending.Count > ShowNext)
                Console.WriteLine($"  ... and {pending.Count - ShowNext} more");

            Console.WriteLine();
            Console.Write("Scan bin if EMPTY   (F=stock found, C=close count, 0=leave): ");

            var raw = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(raw))
            {
                lastMessage = null;
                continue;
            }

            if (raw == "0")
            {
                Console.WriteLine();
                Console.WriteLine($"Count #{countId} left open — {pending.Count} bin(s) still to check.");
                Console.WriteLine("Select the same storage type again to resume.");
                Thread.Sleep(1800);
                return;
            }

            if (string.Equals(raw, "F", StringComparison.OrdinalIgnoreCase))
            {
                lastMessage = ReportStock(command, countId);
                continue;
            }

            if (string.Equals(raw, "C", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine();
                Console.Write($"Close this count with {pending.Count} bin(s) unchecked? (y/N): ");
                var answer = Console.ReadLine();

                if (!string.Equals(answer, "y", StringComparison.OrdinalIgnoreCase))
                {
                    lastMessage = "Count not closed.";
                    continue;
                }

                var closed = command.Close(countId);
                Console.WriteLine();
                Console.WriteLine(closed.FriendlyMessage);

                if (closed.FinalStatus == "REVIEW")
                    Console.WriteLine($"{closed.FindingsToReview} finding(s) need supervisor review.");

                Trace(closed.ResultCode);
                Thread.Sleep(closed.FinalStatus == "REVIEW" ? 2500 : 1500);
                return;
            }

            // Anything else is a bin scan: confirm it empty
            var result = command.ConfirmEmpty(countId, raw);
            lastMessage = FormatBin(raw, result);
        }
    }

    // --------------------------------------------------
    // Stock found: bin, then each pallet in it
    // --------------------------------------------------

    private string ReportStock(ICountCommandRepository command, int countId)
    {
        Console.WriteLine();
        Console.Write("Bin with stock (blank=cancel): ");

        var bin = Console.ReadLine()?.Trim();

        if (string.IsNullOrWhiteSpace(bin))
            return "Cancelled.";

        int corrected = 0;
        int flagged   = 0;

        while (true)
        {
            Console.Write($"Scan pallet in {bin} (blank=done): ");

            var raw = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(raw))
                break;

            var sscc   = ResolveSscc(raw);
            var result = command.ReportStock(countId, bin, sscc);

            Console.WriteLine(DescribeStock(bin, sscc, result));
            Trace(result.ResultCode);

            if (result.FindingCode == "RECORD_CORRECTED")
                corrected++;
            else if (result.FindingCode is "UNKNOWN_UNIT" or "NOT_CORRECTED")
                flagged++;

            // The count, or this bin within it, cannot take findings - scanning
            // more pallets would only repeat the same refusal
            if (result.ResultCode is "ERRCNT03" or "ERRCNT04" or "ERRCNT05")
                break;
        }

        if (corrected == 0 && flagged == 0)
            return $"{bin}: nothing recorded.";

        return $"{bin}: {corrected} corrected, {flagged} recorded for review.";
    }

    private static string DescribeStock(string bin, string sscc, CountStockResult r)
    {
        switch (r.ResultCode)
        {
            case "SUCCNT03":
                return $"  ✓ {sscc} ({r.SkuCode}) is now recorded in {bin} " +
                       $"(the system had it in {r.PreviousBinCode ?? "unknown"}).";

            case "SUCCNT05":
                return $"  = {r.FriendlyMessage}";

            case "WARNCNT03":
            {
                var text = $"  ! {sscc} ({r.SkuCode}) is in {bin} but cannot be moved automatically.";

                if (r.ReasonMessage is not null)
                    text += $"\n    {r.ReasonMessage}";

                // Where it went: the delivery a shipped pallet left on ...
                if (r.ShipmentRef is not null)
                {
                    text += $"\n    Left on {r.ShipmentRef}";

                    if (r.ShippedAt is not null)
                        text += $" ({r.ShippedAt:dd/MM/yyyy HH:mm})";

                    if (!string.IsNullOrWhiteSpace(r.VehicleRef))
                        text += $", vehicle {r.VehicleRef}";

                    text += ".";
                }

                // ... and the order (and customer) it was picked for
                if (r.OrderRef is not null)
                {
                    text += $"\n    Order {r.OrderRef}";

                    if (!string.IsNullOrWhiteSpace(r.CustomerName))
                        text += $" - {r.CustomerName}";

                    text += ".";
                }

                return text + "\n    Recorded for supervisor review.";
            }

            case "WARNCNT02":
                return $"  ! {sscc}: {r.FriendlyMessage}";

            default:
                return $"  x {r.FriendlyMessage}";
        }
    }

    // --------------------------------------------------
    // Finish
    // --------------------------------------------------

    private void Complete(
        ICountQueryRepository   query,
        ICountCommandRepository command,
        int                     countId)
    {
        var closed  = command.Close(countId);
        var session = query.GetSession(countId);

        var needsReview = closed.FinalStatus == "REVIEW";

        Console.Clear();
        Console.WriteLine("──────────────────────────");
        Console.WriteLine(needsReview
            ? $"Count #{countId} finished - NEEDS REVIEW"
            : $"Count #{countId} complete");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine();

        if (session is not null)
        {
            Console.WriteLine($"Storage type:       {session.StorageTypeCode}");
            Console.WriteLine($"Bins checked:       {session.TotalBins}");
            Console.WriteLine($"Confirmed empty:    {session.ConfirmedEmpty}");
            Console.WriteLine($"Stock found:        {session.StockFound}");
            Console.WriteLine($"Filled since start: {session.OccupiedSince}");

            if (needsReview)
            {
                Console.WriteLine();
                Console.WriteLine($"{closed.FindingsToReview} finding(s) need supervisor review.");
                Console.WriteLine("The count stays on the review list until a manager marks it reviewed.");
            }
            else if (session.StockFound > 0)
            {
                Console.WriteLine();
                Console.WriteLine("Everything found was corrected in the system. The details are recorded on the count.");
            }
        }
        else
        {
            Console.WriteLine(closed.FriendlyMessage);
        }

        Trace(closed.ResultCode);
        Console.WriteLine();
        Console.WriteLine("Press any key to continue.");
        Console.ReadKey(true);
    }

    // --------------------------------------------------
    // Helpers
    // --------------------------------------------------

    private string FormatBin(string bin, CountBinResult r)
    {
        var prefix = r.Success && !r.IsWarning ? "✓" : r.IsWarning ? "!" : "x";
        var text   = $"{prefix} {bin}: {r.FriendlyMessage}";

        return _session.UiMode == UiMode.Trace
            ? $"{text}  [{r.ResultCode}]"
            : text;
    }

    private string ResolveSscc(string raw)
    {
        var scan = GtinParser.Parse(raw);

        if (scan.IsValid && scan.Sscc is not null)
        {
            if (_session.UiMode == UiMode.Trace)
                Console.WriteLine($"[SCAN] SSCC={scan.Sscc}");

            return scan.Sscc;
        }

        if (_session.UiMode == UiMode.Trace)
            Console.WriteLine($"[SCAN] No GS1 SSCC — using raw: '{raw}'");

        return raw;
    }

    private void Trace(string resultCode)
    {
        if (_session.UiMode == UiMode.Trace)
            Console.WriteLine($"[TRACE] ResultCode: {resultCode}");
    }
}
