using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Services;
using PeasyWare.CLI.UI;
using PeasyWare.Infrastructure.Bootstrap;
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

            var queryRepo   = _runtime.Repositories.CreateInboundQuery(_session);
            var commandRepo = _runtime.Repositories.CreateInboundCommand(_session);

            var service = new InboundReceivingService(
                queryRepo,
                commandRepo,
                _runtime.ErrorMessageResolver);

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

            Console.Write("Enter receiving bin: ");
            var bin = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(bin))
                return;

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
                Console.Write("Scan SSCC (B=change bin, 0=exit): ");

                var scanInput = Console.ReadLine()?.Trim();

                if (string.Equals(scanInput, "0"))
                    return;

                if (string.Equals(scanInput, "B", StringComparison.OrdinalIgnoreCase))
                {
                    Console.Write("Enter new receiving bin: ");
                    bin = Console.ReadLine()?.Trim() ?? "";
                    continue;
                }

                if (string.IsNullOrWhiteSpace(scanInput))
                    continue;

                var validation = service.ValidateSscc(scanInput, bin);

                if (_session.UiMode == UiMode.Trace)
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
                    _session.UiMode,
                    scanInput,
                    bin);

                if (validation.ClaimExpiresAt.HasValue &&
                    validation.ClaimExpiresAt.Value < DateTime.UtcNow)
                {
                    Console.WriteLine("Claim expired. Please rescan SSCC.");
                    continue;
                }

                Console.Write("Scan SSCC again to confirm (0=cancel): ");
                var confirm = Console.ReadLine()?.Trim();

                if (confirm == "0")
                    continue;

                if (!string.Equals(confirm, scanInput, StringComparison.OrdinalIgnoreCase))
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
                    validation.ClaimToken.Value);

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
