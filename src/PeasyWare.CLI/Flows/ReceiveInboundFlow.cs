using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Services;
using PeasyWare.CLI.UI;
using PeasyWare.Infrastructure.Bootstrap;
using PeasyWare.Infrastructure.Repositories;
using System;

namespace PeasyWare.Application.Flows
{
    public sealed class ReceiveInboundFlow
    {
        private readonly AppRuntime _runtime;
        private readonly SessionContext _session;
        private readonly ILogger? _logger;

        public ReceiveInboundFlow(AppRuntime runtime, SessionContext session)
        {
            _runtime = runtime;
            _session = session;
        }

        public ReceiveInboundFlow(
            AppRuntime runtime,
            SessionContext session,
            ILogger logger)
        {
            _runtime = runtime;
            _session = session;
            _logger = logger;

        }

        public void Run()
        {
            Console.Clear();

            Console.Write("Enter inbound ref: ");
            var inboundRef = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(inboundRef))
                return;

            var queryRepo = _runtime.Repositories.CreateInboundQuery(_session);
            var commandRepo = _runtime.Repositories.CreateInboundCommand(_session);

            var service = new InboundReceivingService(
                queryRepo,
                commandRepo,
                _runtime.ErrorMessageResolver);

            // --------------------------------------------------
            // 1️⃣ Validate inbound summary
            // --------------------------------------------------

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

            // --------------------------------------------------
            // 2️⃣ Ask for bin once
            // --------------------------------------------------

            Console.Write("Enter receiving bin: ");
            var bin = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(bin))
                return;

            // --------------------------------------------------
            // 3️⃣ SSCC receiving loop
            // --------------------------------------------------

            while (true)
            {
                var remaining =
                    queryRepo.GetOutstandingSsccCount(inboundRef);

                if (remaining == 0)
                {
                    Console.WriteLine("Inbound fully received and closed.");
                    Console.ReadKey(true);
                    return;
                }

                Console.WriteLine();
                Console.WriteLine($"Outstanding SSCCs: {remaining}");
                Console.Write("Scan SSCC (B=change bin, 0=exit): ");

                var scanInput = Console.ReadLine()?.Trim();

                if (string.Equals(scanInput, "0"))
                    return;

                if (string.Equals(scanInput, "B",
                        StringComparison.OrdinalIgnoreCase))
                {
                    Console.Write("Enter new receiving bin: ");
                    bin = Console.ReadLine()?.Trim() ?? "";
                    continue;
                }

                if (string.IsNullOrWhiteSpace(scanInput))
                    continue;

                // --------------------------------------------------
                // 4️⃣ Validate SSCC (preview)
                // --------------------------------------------------

                var validation = service.ValidateSscc(scanInput, bin);

                if (_runtime.Settings.DiagnosticsEnabled)
                {
                    Console.WriteLine($"DEBUG -> ExpectedUnitId: {validation.InboundExpectedUnitId}");
                    Console.WriteLine($"DEBUG -> ClaimToken: {validation.ClaimToken}");
                }

                if (!validation.Success)
                {
                    Console.WriteLine(validation.FriendlyMessage);
                    continue;
                }

                ReceiveInboundScreen.RenderSsccPreview(
                    validation,
                    _runtime.Settings.ReceivingUiMode,
                    scanInput,
                    bin);

                if (validation.ClaimExpiresAt.HasValue &&
                    validation.ClaimExpiresAt.Value < DateTime.UtcNow)
                {
                    Console.WriteLine("Claim expired. Please rescan SSCC.");
                    continue;
                }

                // --------------------------------------------------
                // 5️⃣ Double scan confirmation
                // --------------------------------------------------

                Console.Write("Scan SSCC again to confirm (0=cancel): ");
                var confirm = Console.ReadLine()?.Trim();

                if (confirm == "0")
                    continue;

                if (!string.Equals(confirm,
                        scanInput,
                        StringComparison.OrdinalIgnoreCase))
                {
                    Console.WriteLine("Confirmation scan mismatch.");
                    continue;
                }

                if (validation.InboundExpectedUnitId <= 0 ||
                    validation.ClaimToken is null)
                {
                    Console.WriteLine("Invalid SSCC claim. Please rescan.");
                    continue;
                }

                // --------------------------------------------------
                // 6️⃣ Commit receive (authoritative phase)
                // --------------------------------------------------

                var result = service.ConfirmSscc(
                    validation.InboundExpectedUnitId,
                    scanInput,
                    bin,
                    validation.ClaimToken.Value
                );

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