using System.Data;
using Microsoft.Data.SqlClient;
using Xunit;
using Xunit.Abstractions;

namespace PeasyWare.ConcurrencyTests;

/// <summary>
/// Phase 3 concurrency proof - allocation race.
///
/// outbound.usp_allocate_order locks the *order* row with
/// (UPDLOCK, HOLDLOCK), which serializes two allocation attempts on the
/// SAME order. It does not serialize different orders competing for the
/// same SKU: the unit-selection cursor uses WITH (UPDLOCK) alone - no
/// HOLDLOCK - which is the one place in this codebase that deviates from
/// the stated "UPDLOCK, HOLDLOCK on concurrent reads" convention.
///
/// A first pass with 2 contenders per iteration (60 iterations) came back
/// completely clean - every iteration was one clean win, one clean
/// ERRALLOC01 loss, no sign of contention at all. That's a bit suspicious
/// rather than reassuring: the Barrier synchronizes when the *client*
/// sends the call, not when SQL Server's cursor actually reaches the
/// contested row, and everything ahead of that point in the SP
/// (sp_set_session_context, the order-header lookup, the settings read)
/// adds enough drift with only 2 contenders that they likely never
/// actually landed inside the real, narrow lock window.
///
/// This version uses N contenders racing for the SAME single unit per
/// iteration instead of 2 - with more attackers, the odds that at least
/// one overlapping pair lands inside the critical window go up a lot,
/// without needing to artificially widen the window by injecting a delay
/// into the production stored procedure itself.
///
/// There is also a filtered unique index (UX_allocations_active_unit)
/// that should stop true double-allocation at the data layer even if the
/// application-level locking is loose - so the primary hard invariant
/// (never more than one active allocation per unit) may hold regardless.
/// What's separately checked is what happens to everyone who loses: a
/// unique-index violation mid-cursor-loop falls into the generic
/// BEGIN CATCH, which returns ERRORD01 ("order not found") regardless of
/// the real cause - not "the correct busy/claimed error code" the plan
/// calls for, even where no data was actually corrupted.
/// </summary>
[Trait("Category", "Concurrency")]
public sealed class AllocationRaceTests
{
    private const int Iterations = 20;
    private const int ContendersPerIteration = 8;
    private readonly ITestOutputHelper _output;

    public AllocationRaceTests(ITestOutputHelper output)
    {
        _output = output;
    }

    [Fact]
    public async Task Concurrent_allocation_of_last_unit_never_double_allocates()
    {
        var adminUserId = ResolveAdminUserId();
        var (storageTypeId, binId, customerPartyCode) = SetupSharedFixtures(adminUserId);

        var doubleAllocationViolations = new List<string>();
        var misleadingLoserCodes = new List<string>();
        var successCountDistribution = new Dictionary<int, int>();
        var allCodesSeen = new List<string>();

        try
        {
            for (var i = 0; i < Iterations; i++)
            {
                var skuCode = $"RBAC-RACE-SKU-{i}-{Guid.NewGuid():N}"[..40];
                var refs = Enumerable.Range(0, ContendersPerIteration)
                    .Select(c => $"RACE-{i}-{c}-{Guid.NewGuid():N}"[..40])
                    .ToArray();

                var unitId = CreateSkuAndUnit(skuCode, storageTypeId, binId, adminUserId);
                var orderIds = refs.Select(r => CreateOrder(r, customerPartyCode, skuCode, adminUserId)).ToArray();

                using var barrier = new Barrier(ContendersPerIteration);
                var codes = new string?[ContendersPerIteration];
                var tasks = new Task[ContendersPerIteration];

                for (var c = 0; c < ContendersPerIteration; c++)
                {
                    var idx = c;
                    var orderId = orderIds[idx];
                    tasks[c] = Task.Run(() => codes[idx] = AllocateOrder(orderId, adminUserId, barrier));
                }

                await Task.WhenAll(tasks);

                var successCodes = new[] { "SUCORD02", "WARNORD01" };
                var successCount = codes.Count(c => successCodes.Contains(c));
                successCountDistribution[successCount] = successCountDistribution.GetValueOrDefault(successCount) + 1;
                allCodesSeen.AddRange(codes.Select(c => c ?? "?"));

                var activeAllocations = TestDb.ExecuteScalarInt(
                    """
                    SELECT COUNT(*) FROM outbound.outbound_allocations
                    WHERE inventory_unit_id = @unit_id AND allocation_status <> 'CANCELLED';
                    """,
                    cmd => cmd.Parameters.AddWithValue("@unit_id", unitId));

                // Hard invariant: the unit must never end up actively allocated more than once.
                if (activeAllocations > 1)
                {
                    doubleAllocationViolations.Add(
                        $"Iteration {i}: unit {unitId} has {activeAllocations} active allocations. " +
                        $"Codes: [{string.Join(", ", codes)}]");
                }

                // Softer but still-named invariant: if exactly one contender won,
                // everyone else should get a code that actually means "someone
                // else got it" - not a generic/misleading one like ERRORD01.
                if (successCount >= 1)
                {
                    var loserMisses = codes
                        .Where(c => c is "ERRORD01")
                        .ToList();

                    if (loserMisses.Count > 0)
                    {
                        misleadingLoserCodes.Add(
                            $"Iteration {i}: {loserMisses.Count} losing contender(s) got 'ERRORD01' " +
                            "(\"order not found\") instead of a conflict-specific code - " +
                            $"the orders plainly do exist. Full codes: [{string.Join(", ", codes)}]");
                    }
                }

                CleanupIteration(skuCode, refs);
            }
        }
        finally
        {
            CleanupSharedFixtures(storageTypeId, binId, customerPartyCode);
        }

        _output.WriteLine($"Ran {Iterations} iterations x {ContendersPerIteration} contenders each.");
        _output.WriteLine("");
        _output.WriteLine("Successes per iteration (should always be exactly 1):");
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

        if (misleadingLoserCodes.Count > 0)
        {
            _output.WriteLine("");
            _output.WriteLine($"NOTE: {misleadingLoserCodes.Count} iteration(s) had a losing contender get a misleading result code:");
            foreach (var m in misleadingLoserCodes) _output.WriteLine("  " + m);
        }

        Assert.True(doubleAllocationViolations.Count == 0,
            $"Found {doubleAllocationViolations.Count} double-allocation violation(s) out of {Iterations} iterations:\n" +
            string.Join("\n", doubleAllocationViolations));

        Assert.True(misleadingLoserCodes.Count == 0,
            $"Found {misleadingLoserCodes.Count} iteration(s) where a losing contender got a misleading " +
            "result code instead of a conflict-specific one:\n" + string.Join("\n", misleadingLoserCodes));
    }

    // ------------------------------------------------------------------

    private static int ResolveAdminUserId() =>
        TestDb.ExecuteScalarInt("SELECT TOP (1) id FROM auth.users WHERE username = 'admin';");

    private static (int storageTypeId, int binId, string customerPartyCode) SetupSharedFixtures(int adminUserId)
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var storageTypeCode = $"RACE-STYPE-{suffix}";
        var binCode          = $"RACE-BIN-{suffix}";
        var partyCode        = $"_RACE-CUST-{suffix}";

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

        var binId = TestDb.ExecuteScalarInt(
            """
            INSERT INTO locations.bins (bin_code, storage_type_id, capacity, is_active, created_by)
            OUTPUT INSERTED.bin_id
            VALUES (@code, @storage_type_id, 999, 1, @user_id);
            """,
            cmd =>
            {
                cmd.Parameters.AddWithValue("@code", binCode);
                cmd.Parameters.AddWithValue("@storage_type_id", storageTypeId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        TestDb.ExecuteNonQuery(
            """
            INSERT INTO core.parties (party_code, legal_name, display_name, country_code, is_active, created_at)
            VALUES (@code, 'Concurrency Test Customer', 'Concurrency Test Customer', 'GB', 1, SYSUTCDATETIME());
            """,
            cmd => cmd.Parameters.AddWithValue("@code", partyCode));

        return (storageTypeId, binId, partyCode);
    }

    private static int CreateSkuAndUnit(string skuCode, int storageTypeId, int binId, int adminUserId)
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
                cmd.Parameters.AddWithValue("@ref", $"RACE-UNIT-{Guid.NewGuid():N}"[..40]);
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
                cmd.Parameters.AddWithValue("@bin_id", binId);
                cmd.Parameters.AddWithValue("@user_id", adminUserId);
            });

        return unitId;
    }

    private static int CreateOrder(string orderRef, string customerPartyCode, string skuCode, int adminUserId)
    {
        var linesJson = $$"""[{"LineNo":1,"SkuCode":"{{skuCode}}","OrderedQty":1}]""";

        using var conn = TestDb.OpenConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "outbound.usp_create_order";
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.AddWithValue("@order_ref", orderRef);
        cmd.Parameters.AddWithValue("@customer_party_code", customerPartyCode);
        cmd.Parameters.AddWithValue("@lines_json", linesJson);
        cmd.Parameters.AddWithValue("@user_id", adminUserId);
        cmd.Parameters.AddWithValue("@session_id", Guid.NewGuid());

        using var reader = cmd.ExecuteReader();
        if (!reader.Read())
            throw new InvalidOperationException($"usp_create_order returned no rows for {orderRef}.");

        var success = reader.GetBoolean(reader.GetOrdinal("success"));
        if (!success)
        {
            var code = reader.GetString(reader.GetOrdinal("result_code"));
            throw new InvalidOperationException($"usp_create_order failed for {orderRef}: {code}");
        }

        return reader.GetInt32(reader.GetOrdinal("outbound_order_id"));
    }

    /// <summary>
    /// Opens its own connection, then blocks on the barrier so all
    /// concurrent contenders hit ExecuteReader at effectively the same
    /// instant, rather than merely "close together" via Task.WhenAll.
    /// </summary>
    private static string AllocateOrder(int orderId, int adminUserId, Barrier barrier)
    {
        using var conn = TestDb.OpenConnection();
        using var cmd = conn.CreateCommand();
        cmd.CommandText = "outbound.usp_allocate_order";
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.AddWithValue("@outbound_order_id", orderId);
        cmd.Parameters.AddWithValue("@allow_partial", false);
        cmd.Parameters.AddWithValue("@user_id", adminUserId);
        cmd.Parameters.AddWithValue("@session_id", Guid.NewGuid());

        barrier.SignalAndWait();

        using var reader = cmd.ExecuteReader();
        if (!reader.Read())
            return "NO_ROWS";

        return reader.GetString(reader.GetOrdinal("result_code"));
    }

    private static void CleanupIteration(string skuCode, string[] refs)
    {
        TestDb.ExecuteNonQuery(
            $"""
            DELETE a FROM outbound.outbound_allocations a
            JOIN outbound.outbound_lines l ON l.outbound_line_id = a.outbound_line_id
            JOIN outbound.outbound_orders o ON o.outbound_order_id = l.outbound_order_id
            WHERE o.order_ref IN ({string.Join(", ", refs.Select((_, idx) => $"@r{idx}"))});
            """,
            cmd => { for (var i = 0; i < refs.Length; i++) cmd.Parameters.AddWithValue($"@r{i}", refs[i]); });

        TestDb.ExecuteNonQuery(
            $"""
            DELETE l FROM outbound.outbound_lines l
            JOIN outbound.outbound_orders o ON o.outbound_order_id = l.outbound_order_id
            WHERE o.order_ref IN ({string.Join(", ", refs.Select((_, idx) => $"@r{idx}"))});
            """,
            cmd => { for (var i = 0; i < refs.Length; i++) cmd.Parameters.AddWithValue($"@r{i}", refs[i]); });

        TestDb.ExecuteNonQuery(
            $"DELETE FROM outbound.outbound_orders WHERE order_ref IN ({string.Join(", ", refs.Select((_, idx) => $"@r{idx}"))});",
            cmd => { for (var i = 0; i < refs.Length; i++) cmd.Parameters.AddWithValue($"@r{i}", refs[i]); });

        TestDb.ExecuteNonQuery(
            """
            DELETE p FROM inventory.inventory_placements p
            JOIN inventory.inventory_units u ON u.inventory_unit_id = p.inventory_unit_id
            JOIN inventory.skus s ON s.sku_id = u.sku_id
            WHERE s.sku_code = @sku_code;
            """,
            cmd => cmd.Parameters.AddWithValue("@sku_code", skuCode));

        TestDb.ExecuteNonQuery(
            """
            DELETE u FROM inventory.inventory_units u
            JOIN inventory.skus s ON s.sku_id = u.sku_id
            WHERE s.sku_code = @sku_code;
            """,
            cmd => cmd.Parameters.AddWithValue("@sku_code", skuCode));

        TestDb.ExecuteNonQuery(
            "DELETE FROM inventory.skus WHERE sku_code = @sku_code;",
            cmd => cmd.Parameters.AddWithValue("@sku_code", skuCode));
    }

    private static void CleanupSharedFixtures(int storageTypeId, int binId, string customerPartyCode)
    {
        TestDb.ExecuteNonQuery("DELETE FROM locations.bins WHERE bin_id = @id;",
            cmd => cmd.Parameters.AddWithValue("@id", binId));

        TestDb.ExecuteNonQuery("DELETE FROM locations.storage_types WHERE storage_type_id = @id;",
            cmd => cmd.Parameters.AddWithValue("@id", storageTypeId));

        TestDb.ExecuteNonQuery("DELETE FROM audit.party_changes WHERE party_id = (SELECT party_id FROM core.parties WHERE party_code = @code);",
            cmd => cmd.Parameters.AddWithValue("@code", customerPartyCode));

        TestDb.ExecuteNonQuery("DELETE FROM core.parties WHERE party_code = @code;",
            cmd => cmd.Parameters.AddWithValue("@code", customerPartyCode));
    }
}
