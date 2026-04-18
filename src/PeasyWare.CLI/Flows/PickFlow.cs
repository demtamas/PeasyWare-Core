using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Scanning;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace PeasyWare.CLI.Flows;

public sealed class PickFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public PickFlow(AppRuntime runtime, SessionContext session)
    {
        _runtime = runtime;
        _session = session;
    }

    public void Run()
    {
        var queryRepo   = _runtime.Repositories.CreateOutboundQuery(_session);
        var commandRepo = _runtime.Repositories.CreateOutboundCommand(_session);

        while (true)
        {
            Console.Clear();
            Console.WriteLine("──────────────────────────");
            Console.WriteLine("Pick order");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();

            var orders = queryRepo.GetPickableOrders();

            if (orders.Count == 0)
            {
                Console.WriteLine("No orders available to pick.");
                Console.WriteLine();
                Console.WriteLine("Press any key to return.");
                Console.ReadKey(true);
                return;
            }

            Console.WriteLine($"  {"#",-4} {"Order Ref",-16} {"Customer",-24} {"Status",-12} {"Qty"}");
            Console.WriteLine($"  {new string('-', 68)}");

            for (int i = 0; i < orders.Count; i++)
            {
                var o = orders[i];
                Console.WriteLine(
                    $"  {i + 1,-4} {o.OrderRef,-16} {o.CustomerName,-24} {o.OrderStatusCode,-12} {o.TotalAllocated}/{o.TotalOrdered}");
            }

            Console.WriteLine();
            Console.Write("Enter # or order ref (0=back): ");
            var input = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(input) || input == "0")
                return;

            OutboundOrderSummaryDto? order;

            if (int.TryParse(input, out var seq) && seq >= 1 && seq <= orders.Count)
                order = orders[seq - 1];
            else
                order = queryRepo.GetOrderSummary(input);

            if (order is null)
            {
                Console.WriteLine("Order not found.");
                Console.ReadKey(true);
                continue;
            }

            if (order.OrderStatusCode != "ALLOCATED" && order.OrderStatusCode != "PICKING")
            {
                Console.WriteLine($"Order is {order.OrderStatusCode} — cannot pick.");
                Console.ReadKey(true);
                continue;
            }

            var allocations = queryRepo.GetAllocationsForOrder(order.OutboundOrderId);

            if (allocations.Count == 0)
            {
                Console.WriteLine("No pending allocations found for this order.");
                Console.ReadKey(true);
                continue;
            }

            Console.Clear();
            Console.WriteLine($"Order: {order.OrderRef}  |  Customer: {order.CustomerName}");
            if (order.RequiredDate is not null)
                Console.WriteLine($"Required: {order.RequiredDate}");
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine();

            RenderAllocations(allocations);

            Console.WriteLine();
            Console.Write("Destination staging bin (Enter=auto, 0=back): ");
            var destRaw = Console.ReadLine()?.Trim();

            if (destRaw == "0")
                continue;

            string? destinationBinCode = null;

            if (!string.IsNullOrWhiteSpace(destRaw))
            {
                var binScan = GtinParser.Parse(destRaw);
                destinationBinCode = binScan.IsValid && binScan.Sscc is not null
                    ? binScan.Sscc
                    : destRaw.ToUpperInvariant();

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[SCAN] Destination staging bin: '{destinationBinCode}'");
            }

            // ── Picking starts immediately after destination confirmed ──
            var pendingAllocations = allocations
                .Where(a => a.AllocationStatus == "PENDING")
                .ToList();

            var picked  = 0;
            var skipped = 0;

            foreach (var alloc in pendingAllocations)
            {
                Console.Clear();
                Console.WriteLine($"Order: {order.OrderRef}  —  {picked + skipped + 1} of {pendingAllocations.Count}");
                Console.WriteLine("────────────────────────────────────────────────────────────");

                if (_session.UiMode >= UiMode.Standard)
                {
                    Console.WriteLine($"SKU:     {alloc.SkuCode}  {alloc.SkuDescription}");
                    Console.WriteLine($"Qty:     {alloc.AllocatedQty}");
                    if (alloc.BatchNumber is not null)
                        Console.WriteLine($"Batch:   {alloc.BatchNumber}");
                    if (alloc.BestBeforeDate is not null)
                        Console.WriteLine($"BBE:     {alloc.BestBeforeDate}");
                    Console.WriteLine();
                }

                var taskResult = commandRepo.CreatePickTask(alloc.AllocationId, destinationBinCode);

                if (!taskResult.Success)
                {
                    Console.WriteLine($"Could not create pick task: {taskResult.FriendlyMessage}");
                    if (_session.UiMode == UiMode.Trace)
                        Console.WriteLine($"[TRACE] ResultCode: {taskResult.ResultCode}");
                    Console.WriteLine("Press any key to skip this unit.");
                    Console.ReadKey(true);
                    skipped++;
                    continue;
                }

                Console.WriteLine($"Go to:   {taskResult.SourceBinCode}");
                Console.WriteLine($"Pick:    {alloc.Sscc}");
                Console.WriteLine($"Take to: {taskResult.DestinationBinCode}");

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[TRACE] Task: {taskResult.TaskId}  Unit: {taskResult.InventoryUnitId}  Alloc: {alloc.AllocationId}");

                Console.WriteLine();

                bool unitPicked = false;

                while (!unitPicked)
                {
                    // ── Bin scan — validated before SSCC prompt ──────────
                    Console.Write($"Scan source bin [{taskResult.SourceBinCode}] (S=skip, 0=abort): ");
                    var rawBin = Console.ReadLine()?.Trim();

                    if (string.IsNullOrWhiteSpace(rawBin))
                        continue;

                    if (rawBin == "0")
                        goto AbortPicking;

                    if (string.Equals(rawBin, "S", StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine("Unit skipped.");
                        Thread.Sleep(800);
                        skipped++;
                        break;
                    }

                    var binScan     = GtinParser.Parse(rawBin);
                    var resolvedBin = binScan.IsValid && binScan.Sscc is not null
                        ? binScan.Sscc
                        : rawBin;

                    // Pallet label scanned at bin prompt — wrong barcode
                    if (binScan.IsValid && binScan.IsPalletScan && !binScan.IsProductScan)
                    {
                        Console.WriteLine($"That looks like a pallet label. Please scan the bin barcode for {taskResult.SourceBinCode}.");
                        continue;
                    }

                    // Wrong bin scanned
                    if (!string.Equals(resolvedBin, taskResult.SourceBinCode, StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine($"Wrong bin. Expected: {taskResult.SourceBinCode}");
                        continue;
                    }

                    // ── SSCC scan ────────────────────────────────────────
                    Console.Write($"Scan pallet SSCC [{alloc.Sscc}]: ");
                    var rawSscc = Console.ReadLine()?.Trim();

                    if (string.IsNullOrWhiteSpace(rawSscc))
                        continue;

                    var ssccScan     = GtinParser.Parse(rawSscc);
                    var resolvedSscc = ssccScan.IsValid && ssccScan.Sscc is not null
                        ? ssccScan.Sscc
                        : rawSscc;

                    if (_session.UiMode == UiMode.Trace)
                        Console.WriteLine($"[SCAN] Bin: '{resolvedBin}'  SSCC: '{resolvedSscc}'");

                    var confirmResult = commandRepo.ConfirmPickTask(
                        taskResult.TaskId,
                        resolvedBin,
                        resolvedSscc);

                    Console.WriteLine(confirmResult.FriendlyMessage);

                    if (confirmResult.Success)
                    {
                        picked++;
                        unitPicked = true;
                        Thread.Sleep(800);
                    }
                    else
                    {
                        if (_session.UiMode == UiMode.Trace)
                            Console.WriteLine($"[TRACE] ResultCode: {confirmResult.ResultCode}");
                        Console.WriteLine();
                    }
                }
            }

            AbortPicking:

            Console.Clear();
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine($"Pick session complete — Order: {order.OrderRef}");
            Console.WriteLine($"Picked:  {picked}");
            if (skipped > 0)
                Console.WriteLine($"Skipped: {skipped}");
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine();
            Console.WriteLine("Press any key to return.");
            Console.ReadKey(true);
        }
    }

    private void RenderAllocations(IReadOnlyList<OutboundAllocationDto> allocations)
    {
        Console.WriteLine($"  {"Line",-5} {"SKU",-10} {"Qty",9}  {"SSCC",-22} {"Bin",-10} {"Status"}");
        Console.WriteLine($"  {new string('-', 74)}");

        foreach (var a in allocations)
            Console.WriteLine(
                $"  {a.LineNo,-5} {a.SkuCode,-10} {a.AllocatedQty}/{a.OrderedQty,-6}  {a.Sscc,-22} {a.SourceBinCode,-10} {a.AllocationStatus}");
    }
}
