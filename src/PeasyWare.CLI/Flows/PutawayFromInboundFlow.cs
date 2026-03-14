using PeasyWare.Application.Contexts;
using PeasyWare.Infrastructure.Bootstrap;
using PeasyWare.Infrastructure.Repositories;
using System;
using System.Threading;

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
            var queryRepo = new SqlInventoryQueryRepository(
                _runtime.ConnectionFactory,
                _session.SessionId,
                _session.UserId,
                _runtime.ErrorMessageResolver);

            var commandRepo = new SqlWarehouseTaskCommandRepository(
                _runtime.ConnectionFactory,
                _session.SessionId,
                _session.UserId,
                _runtime.ErrorMessageResolver,
                _runtime.Logger);

            while (true)
            {
                Console.Clear();

                Console.WriteLine("──────────────────────────");
                Console.WriteLine("Putaway from inbound");
                Console.WriteLine("──────────────────────────");

                // TRACE mode visibility
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
                    Console.WriteLine($"Pallet: {sscc}");
                    Console.WriteLine($"Task ID: {result.TaskId}");
                    Console.WriteLine($"Suggested Bin: {result.DestinationBinCode}");
                    Console.WriteLine("------------------------------------------------------------");

                    Console.WriteLine();
                    Console.Write("Scan destination bin (C=cancel): ");
                    var destination = Console.ReadLine()?.Trim();

                    if (string.IsNullOrWhiteSpace(destination))
                        continue;

                    if (destination.Equals("C", StringComparison.OrdinalIgnoreCase))
                    {
                        Console.WriteLine("Putaway cancelled.");
                        Thread.Sleep(2000);
                        continue;
                    }

                    var confirmResult = commandRepo.ConfirmPutawayTask(
                        result.TaskId,
                        destination
                    );

                    Console.WriteLine(confirmResult.FriendlyMessage);

                    if (confirmResult.Success)
                    {
                        Console.WriteLine("Putaway completed successfully.");
                        Thread.Sleep(1000);
                    }
                    else
                    {
                        Console.WriteLine("Press any key to continue...");
                        Console.ReadKey(true);
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