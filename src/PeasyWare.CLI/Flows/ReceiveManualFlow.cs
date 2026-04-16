using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Scanning;
using PeasyWare.CLI.UI;
using PeasyWare.Infrastructure.Bootstrap;
using System;

namespace PeasyWare.CLI.Flows;

public sealed class ReceiveManualFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;
    private readonly string?        _inboundRef;

    public ReceiveManualFlow(AppRuntime runtime, SessionContext session)
    {
        _runtime = runtime;
        _session = session;
    }

    public ReceiveManualFlow(AppRuntime runtime, SessionContext session, string inboundRef)
    {
        _runtime    = runtime;
        _session    = session;
        _inboundRef = inboundRef;
    }

    public void Run()
    {
        Console.Clear();

        string? inboundRef = _inboundRef;

        if (string.IsNullOrWhiteSpace(inboundRef))
        {
            Console.Write("Enter inbound ref: ");
            inboundRef = Console.ReadLine()?.Trim();
        }

        if (string.IsNullOrWhiteSpace(inboundRef))
            return;

        var queryRepo   = _runtime.Repositories.CreateInboundQuery(_session);
        var commandRepo = _runtime.Repositories.CreateInboundCommand(_session);

        if (_inboundRef is null)
        {
            var summary = queryRepo.GetInboundSummary(inboundRef);

            if (!summary.Exists)
            {
                Console.WriteLine("Inbound not found.");
                Console.ReadKey(true);
                return;
            }

            if (!summary.IsReceivable)
            {
                Console.WriteLine("Inbound is not in a receivable state.");
                Console.ReadKey(true);
                return;
            }
        }

        Console.Write("Enter receiving bin: ");
        var bin = Console.ReadLine()?.Trim();

        if (string.IsNullOrWhiteSpace(bin))
            return;

        while (true)
        {
            Console.Clear();
            Console.WriteLine($"Manual receive — {inboundRef}  |  Bin: {bin}");
            Console.WriteLine();

            // ------------------------------------------------
            // Step 2 — First scan
            // ------------------------------------------------
            Console.Write("Scan first label (B=change bin, 0=exit): ");
            var firstRaw = Console.ReadLine()?.Trim();

            if (firstRaw == "0") return;

            if (string.Equals(firstRaw, "B", StringComparison.OrdinalIgnoreCase))
            {
                Console.Write("Enter new bin: ");
                bin = Console.ReadLine()?.Trim() ?? bin;
                continue;
            }

            if (string.IsNullOrWhiteSpace(firstRaw)) continue;

            var firstScan = GtinParser.Parse(firstRaw);

            if (_session.UiMode == UiMode.Trace && firstScan.IsValid)
                RenderScanTrace("SCAN 1", firstScan);

            InboundLineByEanDto? line  = null;
            string?              sscc  = null;
            string?              batch = null;
            DateOnly?            bbe   = null;

            if (firstScan.IsValid && firstScan.IsProductScan)
            {
                line = queryRepo.GetReceivableLineByEan(inboundRef, firstScan.Gtin!);

                if (line is null)
                {
                    Console.WriteLine($"Material not expected on this inbound. (GTIN: {firstScan.Gtin})");
                    Console.ReadKey(true);
                    continue;
                }

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[SCAN 1] Matched by: {line.MatchedBy}  Line: {line.InboundLineId}");

                batch = firstScan.Batch;
                bbe   = firstScan.BestBefore;
                sscc  = firstScan.Sscc;
            }
            else if (firstScan.IsValid && firstScan.IsPalletScan)
            {
                sscc  = firstScan.Sscc;
                bbe   = firstScan.BestBefore;
                batch = firstScan.Batch;

                if (_session.UiMode >= UiMode.Standard)
                    Console.WriteLine($"Pallet SSCC captured: {sscc}");
            }
            else
            {
                line = queryRepo.GetReceivableLineByEan(inboundRef, firstRaw);

                if (line is null)
                {
                    Console.WriteLine("Barcode not recognised and SKU not found on this inbound.");
                    Console.ReadKey(true);
                    continue;
                }

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[SCAN 1] Matched by: {line.MatchedBy}  Line: {line.InboundLineId}");
            }

            // ------------------------------------------------
            // Step 3a — need product label (have SSCC, no material)
            // ------------------------------------------------
            if (line is null)
            {
                while (true)
                {
                    Console.Write("Scan product label (0=back): ");
                    var secondRaw = Console.ReadLine()?.Trim();

                    if (secondRaw == "0") break;
                    if (string.IsNullOrWhiteSpace(secondRaw)) continue;

                    var secondScan = GtinParser.Parse(secondRaw);

                    if (_session.UiMode == UiMode.Trace && secondScan.IsValid)
                        RenderScanTrace("SCAN 2", secondScan);

                    var lookupKey = secondScan.IsValid && secondScan.Gtin is not null
                        ? secondScan.Gtin
                        : secondRaw;

                    line = queryRepo.GetReceivableLineByEan(inboundRef, lookupKey);

                    if (line is null)
                    {
                        Console.WriteLine($"Material not expected on this inbound. ({lookupKey})");
                        continue;
                    }

                    if (_session.UiMode == UiMode.Trace)
                        Console.WriteLine($"[SCAN 2] Matched by: {line.MatchedBy}  Line: {line.InboundLineId}");

                    batch ??= secondScan.Batch;
                    bbe   ??= secondScan.BestBefore;
                    break;
                }

                if (line is null) continue;
            }

            // ------------------------------------------------
            // Step 3b — need SSCC (have material, no SSCC)
            // ------------------------------------------------
            if (sscc is null)
            {
                while (true)
                {
                    Console.Write("Scan SSCC label (0=back): ");
                    var secondRaw = Console.ReadLine()?.Trim();

                    if (secondRaw == "0") break;
                    if (string.IsNullOrWhiteSpace(secondRaw)) continue;

                    var secondScan = GtinParser.Parse(secondRaw);

                    if (_session.UiMode == UiMode.Trace && secondScan.IsValid)
                        RenderScanTrace("SCAN 2", secondScan);

                    if (!secondScan.IsValid || secondScan.Sscc is null)
                    {
                        Console.WriteLine("This scan does not contain an SSCC. Please scan the pallet barcode.");
                        continue;
                    }

                    sscc   = secondScan.Sscc;
                    batch ??= secondScan.Batch;
                    bbe   ??= secondScan.BestBefore;
                    break;
                }

                if (sscc is null) continue;
            }

            // ------------------------------------------------
            // Step 4 — Quantity
            // Auto-accept standard HU qty when available.
            // Q at confirmation allows changing it.
            // ------------------------------------------------
            int qty;

            if (line.StandardHuQuantity.HasValue)
            {
                qty = Math.Min(line.StandardHuQuantity.Value, line.OutstandingQty);

                if (_session.UiMode >= UiMode.Standard)
                    Console.WriteLine($"Quantity: {qty}  [standard HU qty]");
            }
            else
            {
                qty = ReceiveManualScreen.PromptQuantityWithDefault(null, line.OutstandingQty);
                if (qty == 0) continue;
            }

            // ------------------------------------------------
            // Step 5 — Batch + BBE
            // ------------------------------------------------
            batch = ReceiveManualScreen.PromptBatch(batch, line.IsBatchRequired);
            if (batch is null && line.IsBatchRequired) continue;

            bbe = ReceiveManualScreen.PromptBbe(bbe);

            // ------------------------------------------------
            // Step 6 — Review
            // ------------------------------------------------
            ReceiveManualScreen.RenderScanPreview(line, sscc, batch, bbe, bin, _session.UiMode);

            // ------------------------------------------------
            // Step 7 — Confirmation scan
            // Q = change qty (straight to number entry, no intermediate step)
            // 0 = cancel
            // ------------------------------------------------
            string? confirmedSscc = null;

            while (true)
            {
                Console.Write($"Scan SSCC to confirm, Q=change qty [{qty}] (0=cancel): ");
                var confirmRaw = Console.ReadLine()?.Trim();

                if (confirmRaw == "0") break;
                if (string.IsNullOrWhiteSpace(confirmRaw)) continue;

                if (string.Equals(confirmRaw, "Q", StringComparison.OrdinalIgnoreCase))
                {
                    // Go straight to number entry — capped at outstanding qty
                    var newQty = ReceiveManualScreen.PromptQuantityChange(line.OutstandingQty);
                    if (newQty == 0) break;
                    qty = newQty;
                    ReceiveManualScreen.RenderScanPreview(line, sscc, batch, bbe, bin, _session.UiMode);
                    continue;
                }

                var confirmScan = GtinParser.Parse(confirmRaw);

                var confirmSscc = confirmScan.IsValid && confirmScan.Sscc is not null
                    ? confirmScan.Sscc
                    : confirmRaw;

                if (!string.Equals(confirmSscc, sscc, StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine($"SSCC mismatch. Expected: {sscc}");
                    continue;
                }

                confirmedSscc = confirmSscc;
                break;
            }

            if (confirmedSscc is null) continue;

            // ------------------------------------------------
            // Step 8 — Execute
            // ------------------------------------------------
            var result = commandRepo.ReceiveInboundLine(
                inboundLineId:  line.InboundLineId,
                receivedQty:    qty,
                stagingBinCode: bin,
                externalRef:    sscc,
                batchNumber:    batch,
                bestBeforeDate: bbe.HasValue
                    ? new DateTime(bbe.Value.Year, bbe.Value.Month, bbe.Value.Day)
                    : null);

            Console.WriteLine();
            Console.WriteLine(result.FriendlyMessage);

            if (_session.UiMode == UiMode.Trace && !result.Success)
                Console.WriteLine($"[TRACE] ResultCode: {result.ResultCode}");

            if (!result.Success)
            {
                Console.ReadKey(true);
                continue;
            }

            var remaining = queryRepo.GetReceivableLines(inboundRef)
                .Any(l => l.OutstandingQty > 0);

            if (!remaining)
            {
                Console.WriteLine("All lines fully received. Inbound closed.");
                Console.ReadKey(true);
                return;
            }

            Console.ReadKey(true);
        }
    }

    private static void RenderScanTrace(string label, GtinScanResult scan)
    {
        Console.WriteLine($"[{label}] IsPallet={scan.IsPalletScan} IsProduct={scan.IsProductScan}");
        if (scan.Sscc       is not null) Console.WriteLine($"[{label}] SSCC:  {scan.Sscc}");
        if (scan.Gtin       is not null) Console.WriteLine($"[{label}] GTIN:  {scan.Gtin}");
        if (scan.Batch      is not null) Console.WriteLine($"[{label}] Batch: {scan.Batch}");
        if (scan.BestBefore is not null) Console.WriteLine($"[{label}] BBE:   {scan.BestBefore:dd-MM-yyyy}");
    }
}
