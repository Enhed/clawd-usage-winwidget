// Offline fixture for tools/smoke.ps1 -MockClaude. Unsupported commands fail closed.
using System;

internal static class MockClaude
{
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--version")
        {
            Console.WriteLine("2.0.0 (Claude Code smoke fixture)");
            return 0;
        }
        if (args.Length == 2 && args[0] == "auth" && args[1] == "status")
        {
            Console.WriteLine("{\"loggedIn\":true,\"email\":\"smoke@example.invalid\",\"subscriptionType\":\"pro\"}");
            return 0;
        }
        if (args.Length == 5 && args[0] == "-p" && args[1] == "/usage" &&
            args[2] == "--output-format" && args[3] == "text" && args[4] == "--no-session-persistence")
        {
            Console.WriteLine("Current session: 37% resets Oct 28, 7:30am");
            Console.WriteLine("Current week (all models): 68% resets Oct 31, 6am");
            Console.WriteLine("Current week (Fable): 12% resets Oct 31, 6am");
            Console.WriteLine("Last 24h: 24 requests, 3 sessions");
            Console.WriteLine("  12% of your usage came from subagent-heavy sessions");
            return 0;
        }
        Console.Error.WriteLine("Mock Claude refuses unsupported arguments.");
        return 2;
    }
}
