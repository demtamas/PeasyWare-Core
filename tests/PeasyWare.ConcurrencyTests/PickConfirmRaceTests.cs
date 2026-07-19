using System.Data;
using Microsoft.Data.SqlClient;
using Xunit;
using Xunit.Abstractions;

namespace PeasyWare.ConcurrencyTests;

/// <summary>
/// Phase 3 concurrency proof - pick confirmation double-pick race.
///
/// outbound.usp_pick_confirm locks both the task row and the inventory
/// unit row with (UPDLOCK, HOLDLOCK) - on paper this looks like the
/// well-protected case, the same shape as usp_allocate_order's order
/// lock. The putaway capacity check also looked fine at a glance and
/// turned out not to be, so this is proven with the harness rather than
/// taken on faith.
///
/// Scenario: N pickers scan and confirm the exact same OPN pick task at
/// the same instant. Exactly one should win; everyone else should be
/// rejected, and the unit must never end up picked/moved more than once
/// (checked both via the task's own state and via a duplicate-movement
/// count, since a race that slipped past the task-state check could
/// still show up as a double inventory_movements/allocation update).
/// </summary>
[Trait("Category", "Concurrency")]
public sealed class PickConfirmRaceTests
{
    private const int Iterations = 20;
    private const int ContendersPerIteration = 8;
    private readonly ITestOutputHelper _output;

    public PickConfirmRaceTests(ITestOutputHelper output)
    {
        _output = output;
    }

    [Fact]
    public async Task Concurrent_pick_confirm_never_picks_the_same_task_twice()
    {
        var adminUserId = ResolveAdminUserId();
        var (storageTypeId, sourceBinId, sourceBinCode, stagingBinId) = SetupSharedFixtures(adminUserId);

        var doublePickViolations = new List<string>();
        var successCountDistribution = new Dictionary<int, int>();
        var allCodesSeen = new List<string>();

        try
        {
            for (var i = 0; i < Iterations; i++)
            {
                var skuCode = $"RBAC-PICK-SKU-{i}-{Guid.NewGuid():N}"[..40];
                var externalRef = $"PICK-SSCC-{i}-{Guid.NewGuid():N}";

                var (unitId, taskId) = CreateUnitAndOpenPickTask(
                    skuCode, externalRef, storageTypeId, sourceBinId, stagingBinId, adminUserId);

                using var barrier = new Barrier(ContendersPerIteration);
                var codes = new string?[ContendersPerIteration];
                var tasks = new Task[ContendersPerIteration];

                for (var c = 0; c < ContendersPerIteration; c++)
                {
                    var idx = c;
                    tasks[c] = Task.Run(() =>
                        codes[idx] = ConfirmPick(taskId, sourceBinCode, externalRef, adminUserId, barrier));
                }

                await Task.WhenAll(tasks);

                var successCodes = new[] { "SUCPICK01" };
                var successCount = codes.Count(c => successCodes.Contains(c));
                successCountDistribution[successCount] = successCountDistribution.GetValueOrDefault(successCount) + 1;
                allCodesSeen.AddRange(codes.Select(c => c ?? "?"));

                var confirmedTaskCount = TestDb.ExecuteScalarInt(
                    "SELECT COUNT(*) FROM warehouse.warehouse_tasks WHERE task_id = @task_id AND task_state_code = 'CNF';",
                    cmd => cmd.Parameters.AddWithValue("@task_id", taskId));

                var pickMovementCount = TestDb.ExecuteScalarInt(
                    "SELECT COUNT(*) FROM inventory.inventory_movements WHERE inventory_unit_id = @unit_id AND movement_type = 'PICK';",
                    cmd => cmd.Parameters.AddWithValue("@unit_id", unitId));

                var pkdUnitCount = TestDb.ExecuteScalarInt(
                    "SELECT COUNT(*) FROM inventory.inventory_units WHERE inventory_unit_id = @unit_id AND stock_state_code = 'PKD';",
                    cmd => cmd.Parameters.AddWithValue("@unit_id", unitId));

                // Hard invariant: exactly one confirmation, one movement row, one PKD transition -
                // never zero (if a winner exists) and never more than one.
                if (successCount > 1 || confirmedTaskCount > 1 || pickMovementCount > 1 || pkdUnitCount > 1)
                {
                    doublePickViolations.Add(
                        $"Iteration {i}: successCount={successCount}, confirmedTaskCount={confirmedTaskCount}, " +
                        $"pickMovementCount={pickMovementCount}, pkdUnitCount={pkdUnitCount}. Codes: [{string.Join(", ", codes)}]");
                }
                else if (successCount == 1 && (confirmedTaskCount != 1 || pickMovementCount != 1 || pkdUnitCount != 1))
                {
                    doublePickViolations.Add(
                        $"Iteration {i}: exactly one contender reported success, but downstream state is " +
                        $"inconsistent (confirmedTaskCount={confirmedTaskCount}, pickMovementCount={pickMovementCount}, " +
                        $"pkdUnitCount={pkdUnitCount}). Codes: [{string.Join(", ", codes)}]");
                }

                CleanupIteration(skuCode, unitId, taskId);
            }
        }
        finally
        {
            try
            {
                CleanupSharedFixtures(storageTypeId, sourceBinId, stagingBinId);
            }
            catch (Exception cleanupEx)
            {
                _output.WriteLine($"WARNING: shared-fixture cleanup failed, likely due to an earlier " +
                                   $"exception leaving orphaned rows: {cleanupEx.Message}");
            }
        }

        _output.WriteLine($"Ran {Iterations} iterations x {ContendersPerIteration} contenders each, all vs one pick task.");
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

        Assert.True(doublePickViolations.Count == 0,
            $"Found {doublePickViolations.Count} violation(s) out of {Iterations} iterations:\n" +
            string.Join("\n", doublePickViolations));
    }

    // ------------------------------------------------------------------

    private static int ResolveAdminUserId() =>
        TestDb.ExecuteScalarInt("SELECT TOP (1) id FROM auth.users WHERE username = 'admin';");

    private static (int storageTypeId, int sourceBinId, string sourceBinCode, int stagingBinId) SetupSharedFixtures(int adminUserId)
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var storageTypeCode = $"PICK-STYPE-{suffix}";
        var sourceBinCode   = $"PICK-SRC-{suffix}";
        var stagingBinCode  = $"PICK-STAGE-{suffix}";

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

        var sourceBinId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
            OUTPUT INSERTED.bin_id
            VALUES (@code, @storage_type_id, 999, 1, @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@code", sourceBinCode);
                cmd.Parameters.AddWithValue("@storage_type_id", storageTypeId);
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

        return (storageTypeId, sourceBinId, sourceBinCode, stagingBinId);
    }

    private static (int unitId, int taskId) CreateUnitAndOpenPickTask(
        string skuCode, string externalRef, int storageTypeId, int sourceBinId, int stagingBinId, int adminUserId)
    {
        var skuId = TestDb.ExecuteScalarInt(
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

        var unitId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO inventory.inventory_units
                (sku_id, external_ref, quantity, stock_state_code, stock_status_code, created_by)
            OUTPUT INSERTED.inventory_unit_id
            VALUES (@sku_id, @ref, 1, 'PTW', 'AV', @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@sku_id", skuId);
                cmd.Parameters.AddWithValue("@ref", externalRef);
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
                cmd.Parameters.AddWithValue("@bin_id", sourceBinId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        var taskId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO warehouse.warehouse_tasks
                (task_type_code, inventory_unit_id, source_bin_id, destination_bin_id, task_state_code, expires_at, created_by)
            OUTPUT INSERTED.task_id
            VALUES ('PICK', @unit_id, @source_bin_id, @staging_bin_id, 'OPN', DATEADD(MINUTE, 30, SYSUTCDATETIME()), @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@unit_id", unitId);
                cmd.Parameters.AddWithValue("@source_bin_id", sourceBinId);
                cmd.Parameters.AddWithValue("@staging_bin_id", stagingBinId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        return (unitId, taskId);
    }

    /// <summary>
    /// Opens its own connection, then blocks on the barrier so all
    /// concurrent contenders hit ExecuteReader at effectively the same
    /// instant.
    /// </summary>
    private static string ConfirmPick(int taskId, string sourceBinCode, string externalRef, int adminUserId, Barrier barrier)
    {
        using var conn = TestDb.OpenConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "outbound.usp_pick_confirm";
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.AddWithValue("@task_id", taskId);
        cmd.Parameters.AddWithValue("@scanned_bin_code", sourceBinCode);
        cmd.Parameters.AddWithValue("@scanned_sscc", externalRef);
        cmd.Parameters.AddWithValue("@user_id", adminUserId);
        cmd.Parameters.AddWithValue("@session_id", Guid.NewGuid());

        barrier.SignalAndWait();

        using var reader = cmd.ExecuteReader();
        if (!reader.Read())
            return "NO_ROWS";

        return reader.GetString(reader.GetOrdinal("result_code"));
    }

    private static void CleanupIteration(string skuCode, int unitId, int taskId)
    {
        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.inventory_movements WHERE inventory_unit_id = @unit_id;",
            cmd => cmd.Parameters.AddWithValue("@unit_id", unitId));

        TestDb.ExecuteNonQuery(
            "DELETE FROM warehouse.warehouse_tasks WHERE task_id = @task_id;",
            cmd => cmd.Parameters.AddWithValue("@task_id", taskId));

        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.inventory_placements WHERE inventory_unit_id = @unit_id;",
            cmd => cmd.Parameters.AddWithValue("@unit_id", unitId));

        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.inventory_units WHERE inventory_unit_id = @unit_id;",
            cmd => cmd.Parameters.AddWithValue("@unit_id", unitId));

        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.skus WHERE sku_code = @sku_code;",
            cmd => cmd.Parameters.AddWithValue("@sku_code", skuCode));
    }

    private static void CleanupSharedFixtures(int storageTypeId, int sourceBinId, int stagingBinId)
    {
        TestDb.ExecuteNonQuery("DELETE FROM locations.bins WHERE bin_id IN (@source, @staging);",
            cmd =>
            {
                cmd.Parameters.AddWithValue("@source", sourceBinId);
                cmd.Parameters.AddWithValue("@staging", stagingBinId);
            });

        TestDb.ExecuteNonQuery("DELETE FROM locations.storage_types WHERE storage_type_id = @id;",
            cmd => cmd.Parameters.AddWithValue("@id", storageTypeId));
    }
}
