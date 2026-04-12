using PeasyWare.Application.Contexts;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Threading;
using System.Threading.Tasks;

namespace PeasyWare.CLI.Flows
{
    public class PutawayFromInboundFlow
    {
        private readonly AppRuntime _runtime;
        private readonly SessionContext _session;

        public PutawayFromInboundFlow(AppRuntime runtime, SessionContext session)
        {
            _runtime = runtime;
            _session = session;
        }

        public async Task RunAsync()
        {
            var queryRepo = _runtime.Repositories.CreateInventoryQuery(_session);
            var commandRepo = _runtime.Repositories.CreateWarehouseTaskCommand(_session);

            while (true)
            {
                Console.Clear();

                Console.WriteLine("──────────────────────────");
                Console.WriteLine("Putaway from inbound");
                Console.WriteLine("──────────────────────────");

                if (_runtime.Settings.DiagnosticsEnabled)
                {
                    var awaiting = queryRepo.GetUnitsAwaitingPutawayCount();
                    Console.WriteLine($"TRACE → Pallets awaiting putaway: {awaiting}");
                    Console.WriteLine();
                }

                Console.Write("Scan pallet SSCC (0=exit): ");
                var sscc = Console.ReadLine()?.Trim();

                if (string.IsNullOrWhiteSpace(sscc) || sscc == "0")
                    return;

                try
                {
                    var unit = queryRepo.GetInventoryUnitByExternalRef(sscc);

                    if (unit == null)
                    {
                        Console.WriteLine("Inventory unit not recognised.");
                        Console.ReadKey(true);
                        continue;
                    }

                    var result = commandRepo.CreatePutawayTask(unit.InventoryUnitId);

                    if (!result.Success)
                    {
                        Console.WriteLine(result.FriendlyMessage);
                        Console.ReadKey(true);
                        continue;
                    }

                    Console.WriteLine();
                    Console.WriteLine("------------------------------------------------------------");
                    Console.WriteLine("PUTAWAY TASK CREATED");
                    Console.WriteLine($"Pallet  : {sscc}");
                    Console.WriteLine($"Task ID : {result.TaskId}");
                    Console.WriteLine($"Bin     : {result.DestinationBinCode}");
                    Console.WriteLine("------------------------------------------------------------");
                    Console.WriteLine();

                    while (true)
                    {
                        Console.Write("Scan destination bin (C=cancel): ");
                        var destination = Console.ReadLine()?.Trim();

                        if (string.IsNullOrWhiteSpace(destination))
                            continue;

                        if (destination.Equals("C", StringComparison.OrdinalIgnoreCase))
                        {
                            Console.WriteLine("Putaway cancelled.");
                            Thread.Sleep(2000);
                            break;
                        }

                        // Client-side pre-check — catches mistype before round trip
                        if (!string.Equals(destination, result.DestinationBinCode,
                            StringComparison.OrdinalIgnoreCase))
                        {
                            Console.WriteLine($"Wrong location. Expected: {result.DestinationBinCode}");
                            continue;
                        }

                        var confirmResult = commandRepo.ConfirmPutawayTask(
                            result.TaskId,
                            destination);

                        Console.WriteLine(confirmResult.FriendlyMessage);

                        if (confirmResult.Success)
                        {
                            Thread.Sleep(1000);
                        }
                        else
                        {
                            Console.ReadKey(true);
                        }

                        break;
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"Putaway failed: {ex.Message}");
                    Console.ReadKey(true);
                }
            }
        }
    }
}