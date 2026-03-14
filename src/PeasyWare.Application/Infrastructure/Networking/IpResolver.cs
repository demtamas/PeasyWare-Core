using System.Net;
using System.Net.Sockets;

public static class IpResolver
{
    public static string? GetLocalIPv4()
    {
        try
        {
            var host = Dns.GetHostEntry(Dns.GetHostName());

            var ip = host.AddressList
                .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork);

            return ip?.ToString();
        }
        catch
        {
            return null;
        }
    }
}
