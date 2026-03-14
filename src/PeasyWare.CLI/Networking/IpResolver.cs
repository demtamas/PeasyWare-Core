using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace PeasyWare.CLI.Networking;

public static class IpResolver
{
    public static string? GetLocalIPv4()
    {
        foreach (var networkInterface in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (networkInterface.OperationalStatus != OperationalStatus.Up)
                continue;

            if (networkInterface.NetworkInterfaceType == NetworkInterfaceType.Loopback)
                continue;

            var ipProps = networkInterface.GetIPProperties();

            foreach (var addr in ipProps.UnicastAddresses)
            {
                if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
                {
                    return addr.Address.ToString();
                }
            }
        }

        return null;
    }
}
