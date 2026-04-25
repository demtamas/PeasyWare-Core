using PeasyWare.Tools.Commands;

if (args.Length == 0)
{
    PrintHelp();
    return 0;
}

return args[0].ToLowerInvariant() switch
{
    "build-allinone" => BuildAllInOneCommand.Run(args),
    "reset-db"       => ResetDbCommand.Run(args),
    "seed"           => SeedCommand.Run(args),
    "stats"          => StatsCommand.Run(args),
    "test"           => TestCommand.Run(args),
    "help" or "--help" or "-h" => (PrintHelp(), 0).Item2,
    _ => (PrintUnknown(args[0]), 1).Item2
};

static int PrintHelp()
{
    Console.WriteLine("pwtools — PeasyWare database and development tools");
    Console.WriteLine();
    Console.WriteLine("Commands:");
    Console.WriteLine("  build-allinone          Concatenate all scripts into DEV_AllInOneInOneGo.sql");
    Console.WriteLine("  reset-db --confirm      Drop and recreate DB from Scripts/ in order");
    Console.WriteLine("  seed [file]             Run seed scripts from Scripts/seed/");
    Console.WriteLine("  stats                   Print DB health dashboard");
    Console.WriteLine("  test [--filter <name>]  Run test suite via dotnet test");
    Console.WriteLine();
    Console.WriteLine("Environment variables:");
    Console.WriteLine("  PEASYWARE_DB            SQL Server connection string (required in Release)");
    Console.WriteLine();
    return 0;
}

static int PrintUnknown(string cmd)
{
    Console.WriteLine($"Unknown command: {cmd}");
    Console.WriteLine("Run 'pwtools help' for available commands.");
    return 1;
}
