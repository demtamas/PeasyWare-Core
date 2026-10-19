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
/// Bin count - a BLIND count of the stock in the bins that hold stock.
///
/// The system lists the bins to visit (bin codes only - never what it expects to
/// find in them). For each bin the operator:
///   1. scans the bin label       → the bin is held for the count (nothing can be
///                                   put into it or taken out while it is counted)
///   2. scans every pallet in it, typing the quantity of each
///   3. presses Enter when done   → the system compares, and records any
///                                   difference for a supervisor
///
/// The operator is never shown what the system holds. The one question they are
/// asked is "the quantity differs from the system record - confirm it?" when a
/// pallet the system has in this bin is entered with a different quantity; the
/// system's figure is not shown. Nothing the operator does here changes a stock
/// record: differences are only recorded, and a supervisor decides what to do.
///
/// A whole warehouse can be counted the same way: choose "S" (sweep) to count
/// every storage type in one go. Choose "A" (ad hoc) to count a hand-picked list
/// of bins instead - a spot check or a suspected problem - empty bins included.
///
/// A count is left open when the operator exits, and resumed by choosing the same
/// scope again; a bin left half-counted is resumed with its scans kept. It closes
/// itself when the last bin is done, or the operator can close it early (C).
///
/// UiMode applies as elsewhere: Trace adds the result codes.
/// </summary>
public sealed class CountBinFlow
{
    private const int ShowNext = 12;

    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public CountBinFlow(AppRuntime runtime, SessionContext session)
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
            Console.WriteLine("Count — Bins (blind)");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();

            var types = query.GetBinCountSummary();

            var open = query.GetSessions(needsAttentionOnly: true)
                .Where(s => s.CountTypeCode == "BIN_COUNT" && s.StatusCode == "OPEN")
                .ToList();

            var openSweep = open.FirstOrDefault(s => s.IsSweep);
            var openAdHoc = open.Where(s => s.IsAdHoc).ToList();

            // No early "nothing to count" exit: an ad hoc count can name an empty bin,
            // so there is always something the operator can choose.
            if (types.Count == 0)
            {
                Console.WriteLine("No storage type has bins holding stock to count.");
                Console.WriteLine("(Ad hoc still lets you count any bin, empty or not.)");
                Console.WriteLine();
            }

            for (int i = 0; i < types.Count; i++)
            {
                var t = types[i];

                var detail = t.OpenCountId is null
                    ? $"{t.BinsWithStock} bin(s) to count"
                    : $"count in progress — {t.OpenPendingBins ?? 0} left to count";

                Console.WriteLine($"{i + 1}. {t.StorageTypeCode,-10} {t.StorageTypeName,-24} {detail}");
            }

            var sweepDetail = openSweep is null
                ? "every bin that holds stock, in every storage type"
                : $"count in progress — {openSweep.PendingBins + openSweep.CountingBins} left to count";

            Console.WriteLine($"S. {"ALL",-10} {"Sweep",-24} {sweepDetail}");

            var adHocDetail = openAdHoc.Count == 0
                ? "choose the bins to count - empty or occupied"
                : $"{openAdHoc.Count} in progress, or start a new one";

            Console.WriteLine($"A. {"AD HOC",-10} {"Chosen bins",-24} {adHocDetail}");
            Console.WriteLine("0. Back");
            Console.WriteLine();
            Console.Write("Select storage type (S = sweep, A = ad hoc): ");

            var input = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(input) || input == "0")
                return;

            if (string.Equals(input, "A", StringComparison.OrdinalIgnoreCase))
            {
                AdHoc(query, command, openAdHoc);
                continue;
            }

            string? storageTypeCode;
            string  scopeLabel;

            if (string.Equals(input, "S", StringComparison.OrdinalIgnoreCase))
            {
                storageTypeCode = null;
                scopeLabel      = "All storage types";
            }
            else if (int.TryParse(input, out var choice) && choice >= 1 && choice <= types.Count)
            {
                storageTypeCode = types[choice - 1].StorageTypeCode;
                scopeLabel      = storageTypeCode;
            }
            else
            {
                Console.WriteLine("Invalid option.");
                Thread.Sleep(800);
                continue;
            }

            var start = command.StartBinCount(storageTypeCode);

            if (!start.Success)
            {
                Console.WriteLine();
                Console.WriteLine(start.FriendlyMessage);
                Trace(start.ResultCode);
                Console.WriteLine("Press any key to continue.");
                Console.ReadKey(true);
                continue;
            }

            RunCount(query, command, start, scopeLabel);
        }
    }

    // --------------------------------------------------
    // Ad hoc: a hand-picked list of bins
    // --------------------------------------------------

    private void AdHoc(
        ICountQueryRepository          query,
        ICountCommandRepository        command,
        IReadOnlyList<CountSessionDto> open)
    {
        // An ad hoc count already in progress can be resumed instead
        if (open.Count > 0)
        {
            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Count — Ad hoc");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();

            for (int i = 0; i < open.Count; i++)
            {
                var s = open[i];
                var by = s.StartedBy is null ? "" : $"   (started by {s.StartedBy})";

                Console.WriteLine($"{i + 1}. Resume #{s.CountId} — {s.PendingBins + s.CountingBins} of {s.TotalBins} bin(s) left{by}");
            }

            Console.WriteLine("N. New ad hoc count");
            Console.WriteLine("0. Back");
            Console.WriteLine();
            Console.Write("Select: ");

            var pick = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(pick) || pick == "0")
                return;

            if (int.TryParse(pick, out var n) && n >= 1 && n <= open.Count)
            {
                var chosen = open[n - 1];

                RunCount(query, command,
                    new CountStartResult
                    {
                        Success     = true,
                        CountId     = chosen.CountId,
                        TotalBins   = chosen.TotalBins,
                        PendingBins = chosen.PendingBins,
                        Resumed     = true
                    },
                    "Ad hoc");
                return;
            }

            if (!string.Equals(pick, "N", StringComparison.OrdinalIgnoreCase))
            {
                Console.WriteLine("Invalid option.");
                Thread.Sleep(800);
                return;
            }
        }

        var bins = ChooseBins(query);

        if (bins.Count == 0)
            return;

        var start = command.StartAdHocCount(bins);

        if (!start.Success)
        {
            Console.WriteLine();
            Console.WriteLine(start.InvalidBinCode is null
                ? start.FriendlyMessage
                : $"{start.InvalidBinCode}: {start.FriendlyMessage}");
            Trace(start.ResultCode);
            Console.WriteLine("Press any key to continue.");
            Console.ReadKey(true);
            return;
        }

        RunCount(query, command, start, "Ad hoc");
    }

    /// <summary>
    /// The bins the operator wants counted. Any active bin will do, empty or occupied -
    /// each is checked as it is entered, so a wrong-case or unknown code is caught here
    /// rather than refusing the whole list. Returns an empty list if they back out.
    /// </summary>
    private static List<string> ChooseBins(ICountQueryRepository query)
    {
        var bins = new List<string>();
        string? message = null;

        while (true)
        {
            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Count — Ad hoc: choose the bins");
            Console.WriteLine("──────────────────────────");

            if (message is not null)
                Console.WriteLine(message);

            Console.WriteLine();
            Console.WriteLine(bins.Count == 0
                ? "No bins chosen yet. Any active bin can be counted, empty or not."
                : $"{bins.Count} bin(s) chosen: {string.Join(", ", bins)}");

            Console.WriteLine();
            Console.Write("Scan a bin to add   (blank = start counting, - = remove last, X = cancel): ");

            var raw = Console.ReadLine()?.Trim();

            // Blank: start counting what is chosen (or, with nothing chosen, go back)
            if (string.IsNullOrWhiteSpace(raw))
                return bins;

            if (string.Equals(raw, "X", StringComparison.OrdinalIgnoreCase))
                return new List<string>();

            if (raw == "-")
            {
                if (bins.Count == 0)
                {
                    message = "Nothing to remove.";
                }
                else
                {
                    message = $"Removed {bins[^1]}.";
                    bins.RemoveAt(bins.Count - 1);
                }

                continue;
            }

            var bin = IdentifierPolicy.NormaliseBinCode(raw) ?? raw;

            if (bins.Contains(bin, StringComparer.Ordinal))
            {
                message = $"{bin} is already in the list.";
                continue;
            }

            if (!query.IsCountableBin(bin))
            {
                message = $"x {bin}: not an active bin (bin codes must match exactly).";
                continue;
            }

            bins.Add(bin);
            message = $"✓ {bin} added.";
        }
    }

    // --------------------------------------------------
    // One count, bin by bin
    // --------------------------------------------------

    private void RunCount(
        ICountQueryRepository   query,
        ICountCommandRepository command,
        CountStartResult        start,
        string                  scopeLabel)
    {
        var countId = start.CountId;

        string? lastMessage = start.Resumed
            ? $"Resumed count #{countId}."
            : $"Count #{countId} started — {start.TotalBins} bin(s) to count.";

        while (true)
        {
            // Bins still to do: not yet counted, or opened and left part-way
            var todo = query.GetLines(countId)
                .Where(l => l.LineStatusCode is "PENDING" or "COUNTING")
                .ToList();

            if (todo.Count == 0)
            {
                Complete(query, command, countId);
                return;
            }

            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine($"Count — Bins — {scopeLabel}   (#{countId})");
            Console.WriteLine("──────────────────────────");

            if (lastMessage is not null)
                Console.WriteLine(lastMessage);

            Console.WriteLine();
            Console.WriteLine($"{todo.Count} bin(s) still to count. Next:");

            foreach (var line in todo.Take(ShowNext))
            {
                var open = line.LineStatusCode == "COUNTING" ? "   (open - scan to resume)" : "";
                Console.WriteLine($"  Zone {line.ZoneCode ?? "-",-5} {line.BinCode}{open}");
            }

            if (todo.Count > ShowNext)
                Console.WriteLine($"  ... and {todo.Count - ShowNext} more");

            Console.WriteLine();
            Console.Write("Scan bin to count   (C=close count, 0=leave): ");

            var raw = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(raw))
            {
                lastMessage = null;
                continue;
            }

            if (raw == "0")
            {
                Console.WriteLine();
                Console.WriteLine($"Count #{countId} left open — {todo.Count} bin(s) still to count.");
                Console.WriteLine("Select the same storage type again to resume.");
                Thread.Sleep(1800);
                return;
            }

            if (string.Equals(raw, "C", StringComparison.OrdinalIgnoreCase))
            {
                if (TryClose(command, countId, todo.Count))
                    return;

                lastMessage = "Count not closed.";
                continue;
            }

            // Anything else is a bin scan: open the bin and count it
            var binCode = IdentifierPolicy.NormaliseBinCode(raw) ?? raw;
            var opened  = command.OpenBin(countId, binCode);

            if (!opened.Success)
            {
                lastMessage = Describe(binCode, opened.FriendlyMessage, opened.ResultCode, ok: false);
                continue;
            }

            lastMessage = CountBin(command, countId, binCode, opened);
        }
    }

    // --------------------------------------------------
    // One bin: scan each pallet + quantity, then finish
    // --------------------------------------------------

    private string CountBin(
        ICountCommandRepository command,
        int                     countId,
        string                  bin,
        BinCountOpenResult      opened)
    {
        Trace(opened.ResultCode);

        Console.WriteLine();
        Console.WriteLine(opened.Resumed
            ? $"Resumed {bin} — {opened.PalletsScanned} pallet(s) already scanned. Carry on."
            : $"Counting {bin}. Scan every pallet that is in it.");

        var scanned = opened.PalletsScanned;

        while (true)
        {
            Console.Write($"Scan pallet in {bin} (blank = finished, X = cancel this bin): ");

            var raw = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(raw))
            {
                // A stray Enter must not record a half-counted bin
                Console.Write(scanned == 0
                    ? $"  No pallets scanned - confirm {bin} is EMPTY? (y/N): "
                    : $"  Finish {bin} with {scanned} pallet(s) scanned? (y/N): ");

                if (!IsYes(Console.ReadLine()))
                    continue;

                return Finish(command, countId, bin);
            }

            if (string.Equals(raw, "X", StringComparison.OrdinalIgnoreCase))
            {
                Console.Write($"  Cancel counting {bin} and discard its scans? (y/N): ");

                if (!IsYes(Console.ReadLine()))
                    continue;

                var cancelled = command.CancelBin(countId, bin);
                Trace(cancelled.ResultCode);

                return Describe(bin, cancelled.FriendlyMessage, cancelled.ResultCode, cancelled.Success);
            }

            var sscc = ResolveSscc(raw);
            var qty  = ReadQuantity();

            if (qty is null)
            {
                Console.WriteLine("  Pallet skipped - nothing recorded.");
                continue;
            }

            var total = ScanPallet(command, countId, bin, sscc, qty.Value);

            if (total is not null)
                scanned = total.Value;
        }
    }

    /// <summary>
    /// Records one pallet. Asks the operator to confirm a quantity that differs from
    /// the system record - without saying what the system holds - and resumes the bin
    /// if its hold ran out while they were away. Returns the pallets scanned so far,
    /// or null if nothing was recorded.
    /// </summary>
    private int? ScanPallet(
        ICountCommandRepository command,
        int                     countId,
        string                  bin,
        string                  sscc,
        int                     qty)
    {
        var confirm = false;
        var resumed = false;

        while (true)
        {
            var result = command.ScanUnit(countId, bin, sscc, qty, confirm);
            Trace(result.ResultCode);

            // The hold ran out (the operator was away): resume the bin - the scans
            // so far are kept - and carry on, once
            if (result.HoldExpired && !resumed)
            {
                resumed = true;

                var reopened = command.OpenBin(countId, bin);
                Trace(reopened.ResultCode);

                if (!reopened.Success)
                {
                    Console.WriteLine($"  x {reopened.FriendlyMessage}");
                    return null;
                }

                continue;
            }

            if (result.NeedsConfirmation)
            {
                Console.Write($"  The quantity differs from the system record. Confirm {qty}? (y = confirm, n = enter again): ");

                if (IsYes(Console.ReadLine()))
                {
                    confirm = true;
                    continue;
                }

                var again = ReadQuantity();

                if (again is null)
                {
                    Console.WriteLine("  Pallet skipped - nothing recorded.");
                    return null;
                }

                qty     = again.Value;
                confirm = false;
                continue;
            }

            if (result.Success)
            {
                Console.WriteLine(result.Replaced
                    ? $"  ✓ {sscc} updated ({result.PalletsScanned} pallet(s) so far)."
                    : $"  ✓ {sscc} recorded ({result.PalletsScanned} pallet(s) so far).");

                return result.PalletsScanned;
            }

            Console.WriteLine($"  x {result.FriendlyMessage}");
            return null;
        }
    }

    private string Finish(ICountCommandRepository command, int countId, string bin)
    {
        var r = command.FinishBin(countId, bin);
        Trace(r.ResultCode);

        // The bin changed while it was being counted: nothing was recorded, count it again
        if (r.RecountRequired)
            return $"! {bin}: {r.FriendlyMessage}";

        if (!r.Success)
            return Describe(bin, r.FriendlyMessage, r.ResultCode, ok: false);

        // Only THAT there is something for a supervisor - never what it is
        return r.HasDifferences
            ? $"✓ {bin}: counted ({r.PalletsScanned} pallet(s)). Differences recorded for supervisor review."
            : $"✓ {bin}: counted ({r.PalletsScanned} pallet(s)).";
    }

    // --------------------------------------------------
    // Close early / finish
    // --------------------------------------------------

    private bool TryClose(ICountCommandRepository command, int countId, int remaining)
    {
        Console.WriteLine();
        Console.Write($"Close this count with {remaining} bin(s) uncounted? (y/N): ");

        if (!IsYes(Console.ReadLine()))
            return false;

        var closed = command.Close(countId);

        Console.WriteLine();
        Console.WriteLine(closed.FriendlyMessage);

        if (closed.FinalStatus == "REVIEW")
            Console.WriteLine($"{closed.FindingsToReview} finding(s) need supervisor review.");

        Trace(closed.ResultCode);
        Thread.Sleep(closed.Success ? (closed.FinalStatus == "REVIEW" ? 2500 : 1500) : 2500);

        // Refused (a bin still open, say): the count carries on
        return closed.Success;
    }

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
            Console.WriteLine($"Counted:            {session.ScopeText}");
            Console.WriteLine($"Bins counted:       {session.MatchedBins + session.DifferenceBins} of {session.TotalBins}");
            Console.WriteLine($"Bins with differences: {session.DifferenceBins}");

            if (needsReview)
            {
                Console.WriteLine();
                Console.WriteLine($"{closed.FindingsToReview} finding(s) need supervisor review.");
                Console.WriteLine("Nothing has been changed in the system. A supervisor decides what to do about them.");
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

    /// <summary>A whole-number quantity of at least 1, or null if the operator gives up.</summary>
    private static int? ReadQuantity()
    {
        while (true)
        {
            Console.Write("  Quantity counted (blank = skip this pallet): ");

            var raw = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(raw))
                return null;

            if (int.TryParse(raw, out var qty) && qty >= 1)
                return qty;

            Console.WriteLine("  Enter a whole number of at least 1.");
        }
    }

    private static bool IsYes(string? answer) =>
        string.Equals(answer?.Trim(), "y", StringComparison.OrdinalIgnoreCase);

    private string Describe(string bin, string message, string resultCode, bool ok)
    {
        var text = $"{(ok ? "✓" : "x")} {bin}: {message}";

        return _session.UiMode == UiMode.Trace
            ? $"{text}  [{resultCode}]"
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
