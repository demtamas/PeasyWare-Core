using Microsoft.Data.SqlClient;

namespace PeasyWare.Tools.Commands;

/// <summary>
/// Prints a quick health dashboard for the PeasyWare database.
///
/// Shows:
///   - Row counts per key table
///   - Active sessions
///   - Open inbounds / outbounds
///   - Locked SSCC claims
///   - Last 5 audit events
///
/// Usage: pwtools stats
/// </summary>
internal static class StatsCommand
{
    public static int Run(string[] args)
    {
        string cs;
        try { cs = ToolsConfig.GetConnectionString(); }
        catch (Exception ex) { Console.WriteLine($"ERROR: {ex.Message}"); return 1; }

        try
        {
            using var conn = new SqlConnection(cs);
            conn.Open();

            var builder = new SqlConnectionStringBuilder(cs);
            Console.WriteLine($"PeasyWare Stats — {builder.InitialCatalog} on {builder.DataSource}");
            Console.WriteLine($"As of: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC");
            Console.WriteLine(new string('─', 60));
            Console.WriteLine();

            PrintSection("Inventory", new[]
            {
                ("SKUs",              "SELECT COUNT(*) FROM inventory.skus WHERE is_active = 1"),
                ("Inventory units",   "SELECT COUNT(*) FROM inventory.inventory_units WHERE stock_state_code NOT IN ('SHP','REV')"),
                ("Available units",   "SELECT COUNT(*) FROM inventory.inventory_units WHERE stock_state_code = 'PUT' AND stock_status_code = 'AV'"),
                ("Received (staging)","SELECT COUNT(*) FROM inventory.inventory_units WHERE stock_state_code = 'RCD'"),
            }, conn);

            PrintSection("Inbound", new[]
            {
                ("Active inbounds",   "SELECT COUNT(*) FROM inbound.inbound_deliveries WHERE inbound_status_code = 'ACT'"),
                ("Outstanding SSCCs", "SELECT COUNT(*) FROM inbound.inbound_expected_units WHERE expected_unit_state_code = 'EXP'"),
                ("Claimed SSCCs",     "SELECT COUNT(*) FROM inbound.inbound_expected_units WHERE expected_unit_state_code = 'CLM' AND claim_expires_at > SYSUTCDATETIME()"),
                ("Expired claims",    "SELECT COUNT(*) FROM inbound.inbound_expected_units WHERE expected_unit_state_code = 'CLM' AND claim_expires_at <= SYSUTCDATETIME()"),
            }, conn);

            PrintSection("Outbound", new[]
            {
                ("Open orders",       "SELECT COUNT(*) FROM outbound.outbound_orders WHERE order_status_code NOT IN ('SHIPPED','CANCELLED')"),
                ("Allocated orders",  "SELECT COUNT(*) FROM outbound.outbound_orders WHERE order_status_code = 'ALLOCATED'"),
                ("Open shipments",    "SELECT COUNT(*) FROM outbound.shipments WHERE shipment_status NOT IN ('DEPARTED','CANCELLED')"),
            }, conn);

            PrintSection("Warehouse tasks", new[]
            {
                ("Open putaway tasks","SELECT COUNT(*) FROM warehouse.warehouse_tasks WHERE task_type_code = 'PUTAWAY' AND task_state_code = 'OPN'"),
                ("Open pick tasks",   "SELECT COUNT(*) FROM warehouse.warehouse_tasks WHERE task_type_code = 'PICK' AND task_state_code = 'OPN'"),
            }, conn);

            PrintSection("Sessions", new[]
            {
                ("Active sessions",   "SELECT COUNT(*) FROM auth.user_sessions WHERE expires_at > SYSUTCDATETIME()"),
            }, conn);

            // Last 5 audit events
            Console.WriteLine("Recent audit events");
            Console.WriteLine(new string('─', 60));
            PrintRecentEvents(conn);
            Console.WriteLine();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"ERROR: {ex.Message}");
            return 1;
        }

        return 0;
    }

    private static void PrintSection(string title, (string label, string sql)[] queries, SqlConnection conn)
    {
        Console.WriteLine(title);
        Console.WriteLine(new string('─', 60));

        foreach (var (label, sql) in queries)
        {
            try
            {
                using var cmd = new SqlCommand(sql, conn);
                var value     = cmd.ExecuteScalar();
                Console.WriteLine($"  {label,-30} {value,8}");
            }
            catch
            {
                Console.WriteLine($"  {label,-30} {"N/A",8}");
            }
        }

        Console.WriteLine();
    }

    private static void PrintRecentEvents(SqlConnection conn)
    {
        const string sql = """
            SELECT TOP 5
                CONVERT(NVARCHAR(19), logged_at, 120) AS at,
                ISNULL(CONVERT(NVARCHAR(5), user_id), 'sys') AS usr,
                event_name,
                result_code
            FROM audit.trace_logs
            ORDER BY log_id DESC
            """;

        try
        {
            using var cmd    = new SqlCommand(sql, conn);
            using var reader = cmd.ExecuteReader();

            while (reader.Read())
            {
                var at     = reader.GetString(0);
                var usr    = reader.GetString(1);
                var evt    = reader.GetString(2);
                var code   = reader.GetString(3);
                Console.WriteLine($"  {at}  usr={usr,-6}  {evt,-35} {code}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"  (could not read audit log: {ex.Message})");
        }
    }
}
