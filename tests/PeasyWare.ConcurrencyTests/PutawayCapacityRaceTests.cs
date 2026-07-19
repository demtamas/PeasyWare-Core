using System.Data;
using Microsoft.Data.SqlClient;
using Xunit;
using Xunit.Abstractions;

namespace PeasyWare.ConcurrencyTests;

/// <summary>
/// Phase 3 concurrency proof - putaway destination-bin capacity race.
///
/// warehouse.usp_putaway_confirm_task checks destination bin capacity
/// with two unhinted COUNT(*) reads (inventory.inventory_placements,
/// locations.bin_reservations) - no UPDLOCK, no HOLDLOCK, nothing.
/// Unlike the allocation scenario (Phase 3, round 1), there is also no
/// unique constraint anywhere backstopping bin capacity: the PK on
/// inventory_placements is just inventory_unit_id, so nothing at the
/// data layer stops any number of different units sharing one bin_id.
/// warehouse.UX_tasks_open_unit only guarantees one open task per *unit*
/// - it says nothing about two different units' tasks targeting the
/// same destination bin.
///
/// This builds N putaway tasks for N different units, all pointed at
/// the SAME capacity-1 destination bin, and confirms all N at once via
/// a Barrier. If the check-then-act window is real, the bin should end
/// up with more placements than its capacity allows.
/// </summary>
[Trait("Category", "Concurrency")]
public sealed class PutawayCapacityRaceTests
{
    private const int Iterations = 20;
    private const int ContendersPerIteration = 5;
    private readonly ITestOutputHelper _output;

    public PutawayCapacityRaceTests(ITestOutputHelper output)
    {
        _output = output;
    }

    [Fact]
    public async Task Concurrent_putaway_confirm_never_exceeds_destination_bin_capacity()
    {
        var adminUserId = ResolveAdminUserId();
        var (storageTypeId, stagingBinId, destBinId, destBinCode) = SetupSharedFixtures(adminUserId);

        var capacityViolations = new List<string>();
        var successCountDistribution = new Dictionary<int, int>();
        var allCodesSeen = new List<string>();

        try
        {
            for (var i = 0; i < Iterations; i++)
            {
                var skuCode = $"RBAC-PTW-SKU-{i}-{Guid.NewGuid():N}"[..40];
                var unitAndTask = Enumerable.Range(0, ContendersPerIteration)
                    .Select(c => CreateUnitAndOpenTask(i, c, skuCode, storageTypeId, stagingBinId, destBinId, adminUserId))
                    .ToArray();

                using var barrier = new Barrier(ContendersPerIteration);
                var codes = new string?[ContendersPerIteration];
                var tasks = new Task[ContendersPerIteration];

                for (var c = 0; c < ContendersPerIteration; c++)
                {
                    var idx = c;
                    var taskId = unitAndTask[idx].taskId;
                    tasks[c] = Task.Run(() => codes[idx] = ConfirmPutawayTask(taskId, destBinCode, adminUserId, barrier));
                }

                await Task.WhenAll(tasks);

                var successCodes = new[] { "SUCTASK02" };
                var successCount = codes.Count(c => successCodes.Contains(c));
                successCountDistribution[successCount] = successCountDistribution.GetValueOrDefault(successCount) + 1;
                allCodesSeen.AddRange(codes.Select(c => c ?? "?"));

                var finalPlacements = TestDb.ExecuteScalarInt(
                    "SELECT COUNT(*) FROM inventory.inventory_placements WHERE bin_id = @bin_id;",
                    cmd => cmd.Parameters.AddWithValue("@bin_id", destBinId));

                // Hard invariant: a capacity-1 bin must never end up with more than 1 placement.
                if (finalPlacements > 1)
                {
                    capacityViolations.Add(
                        $"Iteration {i}: destination bin (capacity 1) ended up with {finalPlacements} " +
                        $"placements. Codes: [{string.Join(", ", codes)}]");
                }

                CleanupIteration(skuCode, unitAndTask.Select(x => x.unitId).ToArray(), destBinId);
            }
        }
        finally
        {
            // Don't let a cleanup failure mask whatever actually broke the test -
            // if an earlier iteration threw before reaching its own cleanup, this
            // will legitimately fail too (orphaned rows), but that's a symptom,
            // not the root cause - log it and let the real exception propagate.
            try
            {
                CleanupSharedFixtures(storageTypeId, stagingBinId, destBinId);
            }
            catch (Exception cleanupEx)
            {
                _output.WriteLine($"WARNING: shared-fixture cleanup failed, likely due to an earlier " +
                                   $"exception leaving orphaned rows: {cleanupEx.Message}");
            }
        }

        _output.WriteLine($"Ran {Iterations} iterations x {ContendersPerIteration} contenders each, all vs a capacity-1 bin.");
        _output.WriteLine("");
        _output.WriteLine("Successful confirmations per iteration (should always be exactly 1):");
        foreach (var kv in successCountDistribution.OrderBy(kv => kv.Key))
        {
            _output.WriteLine($"  {kv.Key} success(es): {kv.Value} iteration(s)");
        }
        _output.WriteLine("");
        _output.WriteLine("All individual result codes seen, grouped:");
        foreach (var g in allCodesSeen.GroupBy(c => c).OrderByDescending(g => g.Count()))
        {
            _output.WriteLine($"  {g.Key}: {g.Count()}");
        }

        Assert.True(capacityViolations.Count == 0,
            $"Found {capacityViolations.Count} capacity violation(s) out of {Iterations} iterations:\n" +
            string.Join("\n", capacityViolations));
    }

    // ------------------------------------------------------------------

    private static int ResolveAdminUserId() =>
        TestDb.ExecuteScalarInt("SELECT TOP (1) id FROM auth.users WHERE username = 'admin';");

    private static (int storageTypeId, int stagingBinId, int destBinId, string destBinCode) SetupSharedFixtures(int adminUserId)
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var storageTypeCode = $"PTW-STYPE-{suffix}";
        var stagingBinCode  = $"PTW-STAGE-{suffix}";
        var destBinCode     = $"PTW-DEST-{suffix}";

        var storageTypeId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO locations.storage_types (storage_type_code, storage_type_name, created_by)
            OUTPUT INSERTED.storage_type_id
            VALUES (@code, @name, @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@code", storageTypeCode);
                cmd.Parameters.AddWithValue("@name", "Concurrency Test Type");
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        var stagingBinId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
            OUTPUT INSERTED.bin_id
            VALUES (@code, @storage_type_id, 999, 1, @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@code", stagingBinCode);
                cmd.Parameters.AddWithValue("@storage_type_id", storageTypeId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        var destBinId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
            OUTPUT INSERTED.bin_id
            VALUES (@code, @storage_type_id, 1, 1, @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@code", destBinCode);
                cmd.Parameters.AddWithValue("@storage_type_id", storageTypeId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        return (storageTypeId, stagingBinId, destBinId, destBinCode);
    }

    private static (int unitId, int taskId) CreateUnitAndOpenTask(
        int iteration, int contenderIndex, string skuCode, int storageTypeId,
        int stagingBinId, int destBinId, int adminUserId)
    {
        // One SKU per iteration is enough - all contenders' units share it.
        var skuId = TestDb.ExecuteScalarInt(
            """
            SELECT sku_id FROM inventory.skus WHERE sku_code = @code;
            """,
            cmd => cmd.Parameters.AddWithValue("@code", skuCode));

        if (skuId == 0)
        {
            skuId = TestDb.ExecuteScalarInt(
                """
                INSERT INTO inventory.skus (sku_code, sku_description, ean, uom_code, preferred_storage_type_id, created_by)
                OUTPUT INSERTED.sku_id
                VALUES (@code, 'Concurrency Test SKU', @ean, 'EA', @storage_type_id, @user_id);
                """,
                cmd =>
                {
                    cmd.Parameters.AddWithValue("@code", skuCode);
                    cmd.Parameters.AddWithValue("@ean", Guid.NewGuid().ToString("N")[..20]);
                    cmd.Parameters.AddWithValue("@storage_type_id", storageTypeId);
                    cmd.Parameters.AddWithValue("@user_id", adminUserId);
                });
        }

        var unitId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO inventory.inventory_units
                (sku_id, external_ref, quantity, stock_state_code, stock_status_code, created_by)
            OUTPUT INSERTED.inventory_unit_id
            VALUES (@sku_id, @ref, 1, 'RCD', 'AV', @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@sku_id", skuId);
                cmd.Parameters.AddWithValue("@ref", $"PTW-UNIT-{iteration}-{contenderIndex}-{Guid.NewGuid():N}");
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        TestDb.ExecuteNonQuery(
            """
            INSERT INTO inventory.inventory_placements (inventory_unit_id, bin_id, placed_by)
            VALUES (@unit_id, @bin_id, @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@unit_id", unitId);
                cmd.Parameters.AddWithValue("@bin_id", stagingBinId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        var taskId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO warehouse.warehouse_tasks
                (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id, task_state_code, expires_at, created_by)
            OUTPUT INSERTED.task_id
            VALUES ('PUTAWAY', @unit_id, @staging_bin_id, @dest_bin_id, 'OPN', DATEADD(MINUTE, 30, SYSUTCDATETIME()), @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@unit_id", unitId);
                cmd.Parameters.AddWithValue("@staging_bin_id", stagingBinId);
                cmd.Parameters.AddWithValue("@dest_bin_id", destBinId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        return (unitId, taskId);
    }

    /// <summary>
    /// Opens its own connection, then blocks on the barrier so all
    /// concurrent contenders hit ExecuteReader at effectively the same
    /// instant.
    /// </summary>
    private static string ConfirmPutawayTask(int taskId, string destBinCode, int adminUserId, Barrier barrier)
    {
        using var conn = TestDb.OpenConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "warehouse.usp_putaway_confirm_task";
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.AddWithValue("@task_id", taskId);
        cmd.Parameters.AddWithValue("@scanned_bin_code", destBinCode);
        cmd.Parameters.AddWithValue("@user_id", adminUserId);
        cmd.Parameters.AddWithValue("@session_id", Guid.NewGuid());

        barrier.SignalAndWait();

        using var reader = cmd.ExecuteReader();
        if (!reader.Read())
            return "NO_ROWS";

        return reader.GetString(reader.GetOrdinal("result_code"));
    }

    private static void CleanupIteration(string skuCode, int[] unitIds, int destBinId)
    {
        var idParams = string.Join(", ", unitIds.Select((_, idx) => $"@u{idx}"));

        TestDb.ExecuteNonQuery(
            $"DELETE FROM inventory.inventory_movements WHERE inventory_unit_id IN ({idParams});",
            cmd => { for (var i = 0; i < unitIds.Length; i++) cmd.Parameters.AddWithValue($"@u{i}", unitIds[i]); });

        TestDb.ExecuteNonQuery(
            $"DELETE FROM warehouse.warehouse_tasks WHERE inventory_unit_id IN ({idParams});",
            cmd => { for (var i = 0; i < unitIds.Length; i++) cmd.Parameters.AddWithValue($"@u{i}", unitIds[i]); });

        TestDb.ExecuteNonQuery(
            $"DELETE FROM inventory.inventory_placements WHERE inventory_unit_id IN ({idParams});",
            cmd => { for (var i = 0; i < unitIds.Length; i++) cmd.Parameters.AddWithValue($"@u{i}", unitIds[i]); });

        TestDb.ExecuteNonQuery(
            $"DELETE FROM inventory.inventory_units WHERE inventory_unit_id IN ({idParams});",
            cmd => { for (var i = 0; i < unitIds.Length; i++) cmd.Parameters.AddWithValue($"@u{i}", unitIds[i]); });

        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.skus WHERE sku_code = @sku_code;",
            cmd => cmd.Parameters.AddWithValue("@sku_code", skuCode));

        // Belt and braces: whatever ended up in the destination bin this
        // round must be gone before the next iteration reuses it.
        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.inventory_placements WHERE bin_id = @bin_id;",
            cmd => cmd.Parameters.AddWithValue("@bin_id", destBinId));
    }

    private static void CleanupSharedFixtures(int storageTypeId, int stagingBinId, int destBinId)
    {
        TestDb.ExecuteNonQuery("DELETE FROM locations.bins WHERE bin_id IN (@staging, @dest);",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@staging", stagingBinId);
                cmd.Parameters.AddWithValue("@dest", destBinId);
            });

        TestDb.ExecuteNonQuery("DELETE FROM locations.storage_types WHERE storage_type_id = @id;",
            cmd => cmd.Parameters.AddWithValue("@id", storageTypeId));
    }
}
