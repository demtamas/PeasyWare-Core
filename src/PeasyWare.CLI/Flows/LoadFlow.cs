using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Collections.Generic;
using System.Linq;

namespace PeasyWare.CLI.Flows;

/// <summary>
/// Load confirmation flow.
///
/// Operator selects a shipment, then confirms each order is loaded
/// onto the vehicle. No SSCC scanning — loading is an order-level
/// confirmation. The pick flow already confirmed which units are where.
///
/// Flow:
///   1. Show active shipments (OPEN or LOADING)
///   2. Operator selects shipment by # or ref
///   3. Show orders on the shipment — pending numbered, loaded unnumbered
///   4. Operator selects a pending order by # or ref to mark as loaded
///   5. When all orders loaded, auto-exits with confirmation message
/// </summary>
public sealed class LoadFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public LoadFlow(AppRuntime runtime, SessionContext session)
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
            Console.WriteLine("Load confirmation");
            Console.WriteLine("──────────────────────────");
            Console.WriteLine();

            var shipments = queryRepo.GetActiveShipments();

            if (shipments.Count == 0)
            {
                Console.WriteLine("No active shipments found.");
                Console.WriteLine();
                Console.WriteLine("Press any key to return.");
                Console.ReadKey(true);
                return;
            }

            Console.WriteLine($"  {"#",-4} {"Shipment Ref",-18} {"Vehicle",-14} {"Status",-10} {"Loaded"}");
            Console.WriteLine($"  {new string('-', 60)}");

            for (int i = 0; i < shipments.Count; i++)
            {
                var s = shipments[i];
                Console.WriteLine(
                    $"  {i + 1,-4} {s.ShipmentRef,-18} {s.VehicleRef ?? "(none)",-14} {s.ShipmentStatus,-10} {s.OrdersLoaded}/{s.TotalOrders}");
            }

            Console.WriteLine();
            Console.Write("Enter # or shipment ref (0=back): ");
            var input = Console.ReadLine()?.Trim();

            if (string.IsNullOrWhiteSpace(input) || input == "0")
                return;

            var shipment = int.TryParse(input, out var seq) && seq >= 1 && seq <= shipments.Count
                ? shipments[seq - 1]
                : queryRepo.GetShipmentByRef(input);

            if (shipment is null)
            {
                Console.WriteLine("Shipment not found.");
                Console.ReadKey(true);
                continue;
            }

            // ── Order selection loop for this shipment ────────
            while (true)
            {
                Console.Clear();
                Console.WriteLine($"Shipment: {shipment.ShipmentRef}");
                if (shipment.VehicleRef is not null)
                    Console.WriteLine($"Vehicle:  {shipment.VehicleRef}");
                Console.WriteLine("────────────────────────────────────────────────────────────");
                Console.WriteLine();

                var orders = queryRepo.GetOrdersOnShipment(shipment.ShipmentId);

                if (orders.Count == 0)
                {
                    Console.WriteLine("No orders ready to load on this shipment.");
                    Console.WriteLine();
                    Console.WriteLine("Press any key to return.");
                    Console.ReadKey(true);
                    break;
                }

                var pending = orders.Where(o => o.OrderStatusCode != "LOADED").ToList();
                var loaded  = orders.Where(o => o.OrderStatusCode == "LOADED").ToList();

                Console.WriteLine($"  {"#",-4} {"Order Ref",-16} {"Customer",-24} {"Status"}");
                Console.WriteLine($"  {new string('-', 58)}");

                for (int i = 0; i < pending.Count; i++)
                {
                    var o = pending[i];
                    Console.WriteLine($"  {i + 1,-4} {o.OrderRef,-16} {o.CustomerName,-24} {o.OrderStatusCode}");
                }

                foreach (var o in loaded)
                    Console.WriteLine($"  {"  ",-4} {o.OrderRef,-16} {o.CustomerName,-24} LOADED \u2713");

                if (pending.Count == 0)
                {
                    Console.WriteLine();
                    Console.WriteLine("All orders loaded. Press any key to return.");
                    Console.ReadKey(true);
                    break;
                }

                Console.WriteLine();
                Console.Write("Enter # or order ref to confirm loading (0=done): ");
                var orderInput = Console.ReadLine()?.Trim();

                if (string.IsNullOrWhiteSpace(orderInput) || orderInput == "0")
                    break;

                OutboundOrderSummaryDto? selectedOrder;

                if (int.TryParse(orderInput, out var orderSeq) && orderSeq >= 1 && orderSeq <= pending.Count)
                    selectedOrder = pending[orderSeq - 1];
                else
                    selectedOrder = pending.FirstOrDefault(o =>
                        string.Equals(o.OrderRef, orderInput, StringComparison.OrdinalIgnoreCase));

                if (selectedOrder is null)
                {
                    Console.WriteLine("Order not found or already loaded.");
                    Console.ReadKey(true);
                    continue;
                }

                var result = commandRepo.ConfirmLoad(selectedOrder.OutboundOrderId, shipment.ShipmentId);

                Console.WriteLine(result.FriendlyMessage);

                if (_session.UiMode == UiMode.Trace && !result.Success)
                    Console.WriteLine($"[TRACE] ResultCode: {result.ResultCode}");

                System.Threading.Thread.Sleep(800);

                // Refresh shipment summary for updated loaded count
                shipment = queryRepo.GetShipmentByRef(shipment.ShipmentRef) ?? shipment;
            }
        }
    }
}
