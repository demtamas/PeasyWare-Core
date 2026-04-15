using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.CLI.UI;
using PeasyWare.Infrastructure.Bootstrap;
using System;

namespace PeasyWare.CLI.Flows
{
    public sealed class ReverseInboundReceiptFlow
    {
        private readonly AppRuntime _runtime;
        private readonly SessionContext _session;

        public ReverseInboundReceiptFlow(AppRuntime runtime, SessionContext session)
        {
            _runtime = runtime;
            _session = session;
        }

        public void Run()
        {
            // Role guard — manager and admin only
            if (_session.UiMode < UiMode.Standard)
            {
                Console.WriteLine("You do not have permission to perform reversals.");
                Console.ReadKey(true);
                return;
            }

            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Reverse inbound receipt");
            Console.WriteLine("──────────────────────────");

            Console.Write("Enter inbound ref: ");
            var inboundRef = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(inboundRef))
                return;

            var queryRepo   = _runtime.Repositories.CreateInboundQuery(_session);
            var commandRepo = _runtime.Repositories.CreateInboundCommand(_session);

            // --------------------------------------------------
            // Load reversible receipts
            // --------------------------------------------------
            var receipts = queryRepo.GetReceivableReceipts(inboundRef).ToList();

            if (receipts.Count == 0)
            {
                Console.WriteLine("No reversible receipts found for this inbound.");
                Console.WriteLine("Only receipts in RCD state that have not already been reversed are eligible.");
                Console.ReadKey(true);
                return;
            }

            ReverseInboundScreen.RenderReceipts(receipts);

            var selection = ReverseInboundScreen.PromptSelection(receipts.Count);

            if (selection == 0)
                return;

            var selected = receipts[selection - 1];

            // --------------------------------------------------
            // Show what will be reversed and ask for reason
            // --------------------------------------------------
            ReverseInboundScreen.RenderConfirmation(selected);

            var reason = ReverseInboundScreen.PromptReasonText();

            // --------------------------------------------------
            // Double confirmation
            // --------------------------------------------------
            Console.WriteLine();
            Console.Write($"Type YES to confirm reversal of receipt {selected.ReceiptId}: ");
            var confirm = Console.ReadLine()?.Trim();

            if (!string.Equals(confirm, "YES", StringComparison.Ordinal))
            {
                Console.WriteLine("Reversal cancelled.");
                Console.ReadKey(true);
                return;
            }

            // --------------------------------------------------
            // Execute reversal
            // --------------------------------------------------
            var result = commandRepo.ReverseInboundReceipt(
                selected.ReceiptId,
                reasonCode: "MAN",
                reasonText: string.IsNullOrWhiteSpace(reason) ? null : reason);

            Console.WriteLine();
            Console.WriteLine(result.FriendlyMessage);

            if (_session.UiMode == UiMode.Trace && !result.Success)
            {
                Console.WriteLine($"[TRACE] ResultCode: {result.ResultCode}");
            }

            Console.ReadKey(true);
        }
    }
}
