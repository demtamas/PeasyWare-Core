using PeasyWare.Application.Dto;
using PeasyWare.Infrastructure.Settings;
using System;
using System.Collections.Generic;
using System.Text;

namespace PeasyWare.CLI.UI
{
    public static class ReceiveInboundScreen
    {
        public static void RenderLines(IEnumerable<InboundLineDto> lines)
        {
            var list = lines.ToList();

            Console.WriteLine();
            Console.WriteLine("Receivable Lines");
            Console.WriteLine("------------------------------------------------------------");

            if (!list.Any())
            {
                Console.WriteLine("No receivable lines found.");
                Console.WriteLine();
                return;
            }

            for (int i = 0; i < list.Count; i++)
            {
                var l = list[i];
                Console.WriteLine(
                    $"{i + 1,2}. Line {l.LineNo,-3} | {l.SkuCode,-15} | " +
                    $"Outstanding: {l.OutstandingQty,4} | " +
                    $"Received: {l.ReceivedQty,4}/{l.ExpectedQty}");
            }

            Console.WriteLine("------------------------------------------------------------");
        }

        public static int PromptLineSelection(int max)
        {
            while (true)
            {
                Console.Write("Select line number (0 to cancel): ");
                var input = Console.ReadLine();

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

        public static int PromptQuantity(int maxQty)
        {
            while (true)
            {
                Console.Write($"Enter quantity (max {maxQty}): ");
                var input = Console.ReadLine();

                if (int.TryParse(input, out var qty)
                    && qty > 0
                    && qty <= maxQty)
                    return qty;

                Console.WriteLine("Invalid quantity.");
            }
        }

        public static string PromptBin()
        {
            Console.Write("Enter staging bin code: ");
            return Console.ReadLine()?.Trim() ?? "";
        }

        public static void RenderSsccPreview(
            SsccValidationDto dto,
            ReceivingUiMode uiMode,
            string externalRef,
            string stagingBin)
                {
                    Console.WriteLine();
                    Console.WriteLine("------------------------------------------------------------");
                    Console.WriteLine($"SSCC: {externalRef}");
                    Console.WriteLine($"Inbound: {dto.InboundRef}   [{dto.HeaderStatus}]");
                    Console.WriteLine($"SKU: {dto.SkuCode} | {dto.SkuDescription}");
                    Console.WriteLine($"Unit Qty: {dto.ExpectedUnitQty}");
                    Console.WriteLine($"Batch: {dto.BatchNumber}");
                    Console.WriteLine($"BBE: {dto.BestBeforeDate:dd-MM-yyyy}");
                    Console.WriteLine($"Staging Bin: {stagingBin}");

                    if (uiMode == ReceivingUiMode.Trace)
                    {
                        Console.WriteLine();
                        Console.WriteLine("---- TRACE DETAILS ----");
                        Console.WriteLine($"Line State: {dto.LineState}");
                        Console.WriteLine($"Line Expected: {dto.LineExpectedQty}");
                        Console.WriteLine($"Line Received: {dto.LineReceivedQty}");
                        Console.WriteLine($"Outstanding Before: {dto.OutstandingBefore}");
                        Console.WriteLine($"Outstanding After:  {dto.OutstandingAfter}");
                    }

                    Console.WriteLine("------------------------------------------------------------");
                }
    }

}
