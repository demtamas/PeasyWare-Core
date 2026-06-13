using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Scanning;
using PeasyWare.Application.Services;
using PeasyWare.CLI.UI;
using PeasyWare.Infrastructure.Bootstrap;
using System;

namespace PeasyWare.Application.Flows
{
    /// <summary>
    /// SSCC mode inbound receiving flow.
    ///
    /// This flow is strictly for inbounds with pre-advised handling units
    /// (inbound_expected_units rows). Every receive goes through:
    ///   1. ValidateSscc  — claim the expected unit, return preview
    ///   2. ConfirmSscc   — rescan to confirm, write inventory
    ///
    /// SSCC mode = expected-unit, claim-token, pallet-level confirmation.
    /// There is no product-only (GTIN) receive path here.
    /// If a GTIN-only label is scanned, the operator is told to scan the
    /// pallet SSCC — the SSCC is always required in this flow.
    /// </summary>
    public sealed class ReceiveInboundFlow
    {
        private readonly AppRuntime     _runtime;
        private readonly SessionContext _session;
        private readonly string?        _inboundRef;

        public ReceiveInboundFlow(AppRuntime runtime, SessionContext session)
        {
            _runtime = runtime;
            _session = session;
        }

        public ReceiveInboundFlow(AppRuntime runtime, SessionContext session, string inboundRef)
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

            var service = new InboundReceivingService(
                queryRepo,
                commandRepo,
                _runtime.ErrorMessageResolver);

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

                if (!summary.HasExpectedUnits)
                {
                    Console.WriteLine("Inbound is not pre-advised (no SSCCs found).");
                    Console.ReadKey(true);
                    return;
                }
            }

            Console.Write("Enter receiving bin: ");
            var bin = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(bin))
                return;

            if (!queryRepo.BinExists(bin))
            {
                Console.WriteLine($"Bin '{bin}' not found or is inactive. Please check and try again.");
                Console.ReadKey(true);
                return;
            }

            while (true)
            {
                var remaining = queryRepo.GetOutstandingSsccCount(inboundRef);

                if (remaining == 0)
                {
                    Console.WriteLine("Inbound fully received and closed.");
                    Console.ReadKey(true);
                    return;
                }

                Console.WriteLine();
                Console.WriteLine($"Outstanding SSCCs: {remaining}");
                Console.Write("Scan pallet SSCC (B=change bin, 0=exit): ");

                var rawInput = Console.ReadLine()?.Trim();

                if (string.Equals(rawInput, "0"))
                    return;

                if (string.Equals(rawInput, "B", StringComparison.OrdinalIgnoreCase))
                {
                    Console.Write("Enter new receiving bin: ");
                    bin = (Console.ReadLine()?.Trim() ?? "");
                    if (!string.IsNullOrWhiteSpace(bin) && !queryRepo.BinExists(bin))
                    {
                        Console.WriteLine($"Bin '{bin}' not found or is inactive.");
                        bin = "";
                    }
                    continue;
                }

                if (string.IsNullOrWhiteSpace(rawInput))
                    continue;

                var scan = GtinParser.Parse(rawInput);

                if (_session.UiMode == UiMode.Trace && scan.IsValid)
                {
                    Console.WriteLine($"[SCAN] IsPallet={scan.IsPalletScan} IsProduct={scan.IsProductScan}");
                    if (scan.RawScan        is not null) Console.WriteLine($"[SCAN] Raw:          {scan.RawScan}");
                    if (scan.Sscc           is not null) Console.WriteLine($"[SCAN] SSCC:         {scan.Sscc}");
                    if (scan.Gtin           is not null) Console.WriteLine($"[SCAN] GTIN (01):    {scan.Gtin}");
                    if (scan.ContainedGtin  is not null) Console.WriteLine($"[SCAN] GTIN (02):    {scan.ContainedGtin}");
                    if (scan.Batch          is not null) Console.WriteLine($"[SCAN] Batch:        {scan.Batch}");
                    if (scan.SerialNumber   is not null) Console.WriteLine($"[SCAN] Serial:       {scan.SerialNumber}");
                    if (scan.ProductionDate is not null) Console.WriteLine($"[SCAN] Prod date:    {scan.ProductionDate:dd-MM-yyyy}");
                    if (scan.BestBefore     is not null) Console.WriteLine($"[SCAN] BBE:          {scan.BestBefore:dd-MM-yyyy}");
                    if (scan.Quantity       is not null) Console.WriteLine($"[SCAN] Quantity:     {scan.Quantity}");
                }

                // -------------------------------------------------------
                // SSCC mode requires a pallet SSCC. A product-only scan
                // (GTIN, no SSCC) is not a valid receive input in this flow.
                // The operator must scan the pallet barcode.
                // -------------------------------------------------------
                if (scan.IsValid && scan.IsProductScan && !scan.IsPalletScan)
                {
                    Console.WriteLine("Please scan the pallet SSCC barcode, not the product label.");
                    continue;
                }

                var scanInput = scan.IsValid && scan.Sscc is not null
                    ? scan.Sscc
                    : rawInput;

                var validation = service.ValidateSscc(
                    scanInput,
                    bin,
                    scannedBestBefore:    scan.BestBefore,
                    scannedBatch:         scan.Batch,
                    restrictToInboundRef: inboundRef);

                if (_session.UiMode == UiMode.Trace)
                {
                    Console.WriteLine($"[DEBUG] ExpectedUnitId: {validation.InboundExpectedUnitId}");
                    Console.WriteLine($"[DEBUG] ClaimToken:     {validation.ClaimToken}");
                }

                if (!validation.Success)
                {
                    Console.WriteLine(validation.FriendlyMessage);
                    continue;
                }

                ReceiveInboundScreen.RenderSsccPreview(
                    validation, _session.UiMode, scanInput, bin);

                if (validation.ClaimExpiresAt.HasValue &&
                    validation.ClaimExpiresAt.Value < DateTime.UtcNow)
                {
                    Console.WriteLine("Claim expired. Please rescan.");
                    continue;
                }

                Console.Write("Scan SSCC again to confirm (0=cancel): ");
                var confirmRaw = Console.ReadLine()?.Trim();

                if (confirmRaw == "0")
                    continue;

                var confirmScan  = GtinParser.Parse(confirmRaw);
                var confirmInput = confirmScan.IsValid && confirmScan.Sscc is not null
                    ? confirmScan.Sscc
                    : confirmRaw;

                if (!string.Equals(confirmInput, scanInput, StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine("Confirmation scan mismatch.");
                    continue;
                }

                if (validation.InboundExpectedUnitId <= 0 || validation.ClaimToken is null)
                {
                    Console.WriteLine("Invalid SSCC claim. Please rescan.");
                    continue;
                }

                var result = service.ConfirmSscc(
                    validation.InboundExpectedUnitId,
                    scanInput,
                    bin,
                    validation.ClaimToken.Value,
                    batchNumber:    scan.Batch,
                    bestBeforeDate: scan.BestBefore.HasValue
                        ? scan.BestBefore.Value.ToDateTime(TimeOnly.MinValue)
                        : null);

                // ── Batch required but not on label: prompt operator ─────────────
                if (!result.Success && result.ResultCode == "ERRINBL11")
                {
                    Console.WriteLine(result.FriendlyMessage);
                    Console.Write("Enter batch number or scan label (0=cancel): ");
                    var batchInput = Console.ReadLine()?.Trim();

                    if (string.IsNullOrWhiteSpace(batchInput) || batchInput == "0")
                    {
                        Console.WriteLine("Receipt cancelled.");
                        continue;
                    }

                    // Parse as GS1 barcode first — operator may scan a label
                    // containing AI 10 (batch). Fall back to raw input if no
                    // batch AI found (operator typed it manually).
                    var batchScan   = GtinParser.Parse(batchInput);
                    var manualBatch = batchScan.IsValid && batchScan.Batch is not null
                        ? batchScan.Batch
                        : batchInput;

                    if (_session.UiMode == UiMode.Trace && batchScan.IsValid)
                        Console.WriteLine($"[TRACE] Batch extracted from scan: {manualBatch}");

                    result = service.ConfirmSscc(
                        validation.InboundExpectedUnitId,
                        scanInput,
                        bin,
                        validation.ClaimToken.Value,
                        batchNumber:    manualBatch,
                        bestBeforeDate: scan.BestBefore.HasValue
                            ? scan.BestBefore.Value.ToDateTime(TimeOnly.MinValue)
                            : null);
                }

                if (!result.Success)
                {
                    Console.WriteLine(result.FriendlyMessage);
                    continue;
                }

                Console.WriteLine(result.FriendlyMessage);
                Console.WriteLine();
            }
        }
    }
}
