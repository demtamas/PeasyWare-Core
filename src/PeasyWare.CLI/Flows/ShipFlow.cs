using PeasyWare.Application;
using PeasyWare.Application.Contexts;
using PeasyWare.Infrastructure.Bootstrap;
using System;

namespace PeasyWare.CLI.Flows;

/// <summary>
/// Ship confirmation flow.
///
/// Dispatcher selects a shipment and confirms departure.
/// All PICKED/LOADED orders on the shipment must be ready.
/// Calls usp_ship which transitions all units to SHP and closes the shipment.
///
/// Flow:
///   1. Show active shipments (OPEN or LOADING)
///   2. Operator selects shipment by # or ref
///   3. Show shipment summary — orders, loaded count
///   4. Confirm departure
///   5. usp_ship executes — units → SHP, shipment → DEPARTED
/// </summary>
public sealed class ShipFlow
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    public ShipFlow(AppRuntime runtime, SessionContext session)
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
            Console.WriteLine("Confirm departure");
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

            Console.WriteLine($"  {"#",-4} {"Shipment Ref",-18} {"Vehicle",-14} {"Status",-10} {"Picked",-8} {"Loaded"}");
            Console.WriteLine($"  {new string('-', 68)}");

            for (int i = 0; i < shipments.Count; i++)
            {
                var s = shipments[i];
                Console.WriteLine(
                    $"  {i + 1,-4} {s.ShipmentRef,-18} {s.VehicleRef ?? "(none)",-14} {s.ShipmentStatus,-10} {s.OrdersPicked,-8} {s.OrdersLoaded}/{s.TotalOrders}");
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

            // ── Show summary before confirming ──────────────────
            Console.Clear();
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine($"Shipment:  {shipment.ShipmentRef}");
            if (shipment.VehicleRef is not null)
                Console.WriteLine($"Vehicle:   {shipment.VehicleRef}");
            if (shipment.HaulierName is not null)
                Console.WriteLine($"Haulier:   {shipment.HaulierName}");
            if (shipment.PlannedDeparture is not null)
                Console.WriteLine($"Planned:   {shipment.PlannedDeparture}");
            Console.WriteLine($"Status:    {shipment.ShipmentStatus}");
            Console.WriteLine($"Orders:    {shipment.TotalOrders} total  |  {shipment.OrdersPicked} picked  |  {shipment.OrdersLoaded} loaded");
            Console.WriteLine("────────────────────────────────────────────────────────────");
            Console.WriteLine();

            // Warn if not all orders are loaded
            var readyOrders = shipment.OrdersPicked + shipment.OrdersLoaded;
            if (readyOrders < shipment.TotalOrders)
            {
                Console.WriteLine($"⚠  Warning: {shipment.TotalOrders - readyOrders} order(s) are not yet picked or loaded.");
                Console.WriteLine("   These will not be included in the shipment.");
                Console.WriteLine();
            }

            Console.Write("Confirm departure? (Y=yes, 0=cancel): ");
            var confirm = Console.ReadLine()?.Trim();

            if (!string.Equals(confirm, "Y", StringComparison.OrdinalIgnoreCase))
                continue;

            var result = commandRepo.Ship(shipment.ShipmentId);

            Console.WriteLine();
            Console.WriteLine(result.FriendlyMessage);

            if (result.Success)
            {
                if (_session.UiMode >= UiMode.Standard)
                    Console.WriteLine($"Units shipped: {result.UnitsShipped}");

                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[TRACE] ResultCode: {result.ResultCode}");

                Console.WriteLine();
                Console.WriteLine("Press any key to return.");
                Console.ReadKey(true);
                return;
            }
            else
            {
                if (_session.UiMode == UiMode.Trace)
                    Console.WriteLine($"[TRACE] ResultCode: {result.ResultCode}");

                Console.ReadKey(true);
            }
        }
    }
}
