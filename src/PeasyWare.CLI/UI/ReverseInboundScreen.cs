using PeasyWare.Application.Dto;
using System;
using System.Collections.Generic;

namespace PeasyWare.CLI.UI
{
    public static class ReverseInboundScreen
    {
        public static void RenderReceipts(IReadOnlyList<InboundReceiptDto> receipts)
        {
            Console.WriteLine();
            Console.WriteLine("Reversible receipts");
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine($"  {"#",-4} {"Receipt",-8} {"SSCC",-25} {"Qty",-5} {"Bin",-10} {"Received At",-22}");
            Console.WriteLine("────────────────────────────────────────────────────────────");

            for (int i = 0; i < receipts.Count; i++)
            {
                var r = receipts[i];
                Console.WriteLine(
                    $"  {i + 1,-4} {r.ReceiptId,-8} {r.ExternalRef ?? "(no SSCC)",-25} " +
                    $"{r.ReceivedQty,-5} {r.CurrentBinCode ?? "?",-10} {r.ReceivedAt:dd-MM-yyyy HH:mm:ss}");
            }

            Console.WriteLine("────────────────────────────────────────────────────────────");
        }

        public static int PromptSelection(int max)
        {
            while (true)
            {
                Console.Write("Select receipt to reverse (0=cancel): ");
                var input = Console.ReadLine()?.Trim();

                if (int.TryParse(input, out var number))
                {
                    if (number == 0)
                        return 0;

                    if (number >= 1 && number <= max)
                        return number;
                }

                Console.WriteLine("Invalid selection.");
            }
        }

        public static string PromptReasonText()
        {
            Console.Write("Enter reason (or press Enter to skip): ");
            return Console.ReadLine()?.Trim() ?? "";
        }

        public static void RenderConfirmation(InboundReceiptDto receipt)
        {
            Console.WriteLine();
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine("REVERSAL DETAILS");
            Console.WriteLine($"Receipt ID : {receipt.ReceiptId}");
            Console.WriteLine($"SSCC       : {receipt.ExternalRef ?? "(no SSCC)"}");
            Console.WriteLine($"Qty        : {receipt.ReceivedQty}");
            Console.WriteLine($"Bin        : {receipt.CurrentBinCode ?? "?"}");
            Console.WriteLine($"Received   : {receipt.ReceivedAt:dd-MM-yyyy HH:mm:ss}");
            Console.WriteLine("────────────────────────────────────────────────────────────");
        }
    }
}
