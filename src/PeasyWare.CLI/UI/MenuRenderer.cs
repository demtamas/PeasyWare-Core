namespace PeasyWare.CLI.UI;

public static class MenuRenderer
{
    // ==========================================================
    // Main
    // ==========================================================

    public static string ShowMainMenu()
    {
        Console.WriteLine();
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("Main Menu");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. Inbound");
        Console.WriteLine("2. Inventory");
        Console.WriteLine("3. Orders");
        Console.WriteLine("4. Admin");
        Console.WriteLine("7. Logout");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    // ==========================================================
    // Inbound
    // ==========================================================

    public static string ShowInboundMenu()
    {
        Console.WriteLine();
        Console.WriteLine("Inbound");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. Activate inbound");
        Console.WriteLine("2. Receive stock");
        Console.WriteLine("3. Putaway from inbound");
        Console.WriteLine("4. View expected inbounds");
        Console.WriteLine("0. Back");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    // ==========================================================
    // Inventory
    // ==========================================================

    public static string ShowInventoryMenu()
    {
        Console.WriteLine();
        Console.WriteLine("Inventory");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. Query stock");
        Console.WriteLine("2. Query bin");
        Console.WriteLine("3. Query pallet / HU");
        Console.WriteLine("4. Move stock");
        Console.WriteLine("5. Count stock");
        Console.WriteLine("0. Back");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    public static string ShowMoveMenu()
    {
        Console.WriteLine();
        Console.WriteLine("Move Stock");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. Putaway (guided)");
        Console.WriteLine("2. Bin to bin");
        Console.WriteLine("3. Reverse last movement");
        Console.WriteLine("0. Back");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    public static string ShowCountMenu()
    {
        Console.WriteLine();
        Console.WriteLine("Stock Count");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. Cycle count");
        Console.WriteLine("2. Ad-hoc count");
        Console.WriteLine("3. View last differences");
        Console.WriteLine("0. Back");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    // ==========================================================
    // Orders
    // ==========================================================

    public static string ShowOrdersMenu()
    {
        Console.WriteLine();
        Console.WriteLine("Orders");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. View open orders");
        Console.WriteLine("2. Pick order");
        Console.WriteLine("3. Cross-dock");
        Console.WriteLine("4. Load");
        Console.WriteLine("5. Ship");
        Console.WriteLine("0. Back");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    // ==========================================================
    // Admin
    // ==========================================================

    public static string ShowAdminMenu()
    {
        Console.WriteLine();
        Console.WriteLine("Admin");
        Console.WriteLine("──────────────────────────");
        Console.WriteLine("1. View active sessions");
        Console.WriteLine("2. Kill session");
        Console.WriteLine("3. System status");
        Console.WriteLine("4. Diagnostics");
        Console.WriteLine("0. Back");
        Console.WriteLine();

        Console.Write("Select option: ");
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }
}
