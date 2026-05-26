using PeasyWare.Application.Dto;
using PeasyWare.Application.Services;
using System;
using System.Diagnostics;
using System.Drawing.Printing;
using System.IO;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Services;

/// <summary>
/// Prints or previews a delivery note.
/// Mode A (silent): renders HTML, prints via WebBrowser silently to named printer.
/// Mode B (browser): renders HTML, opens in default browser for manual print.
/// </summary>
public static class DeliveryNotePrinter
{
    /// <summary>
    /// Opens the delivery note in the system default browser for manual print.
    /// </summary>
    public static string OpenInBrowser(ShipmentManifestDto manifest, string? templatePath = null)
    {
        var html     = DeliveryNoteRenderer.Render(manifest, templatePath);
        var tempFile = WriteTempFile(manifest.ShipmentRef, html);

        Process.Start(new ProcessStartInfo
        {
            FileName        = tempFile,
            UseShellExecute = true
        });

        return tempFile;
    }

    /// <summary>
    /// Prints silently to the specified printer (or system default if blank).
    /// Falls back to browser if silent print fails.
    /// </summary>
    public static void PrintSilent(
        ShipmentManifestDto manifest,
        string?             printerName  = null,
        int                 copies       = 1,
        string?             templatePath = null)
    {
        var html     = DeliveryNoteRenderer.Render(manifest, templatePath);
        var tempFile = WriteTempFile(manifest.ShipmentRef, html);

        try
        {
            using var browser = new WebBrowser { ScriptErrorsSuppressed = true };

            browser.DocumentCompleted += (_, _) =>
            {
                try
                {
                    if (!string.IsNullOrWhiteSpace(printerName))
                    {
                        var defaultPrinter = new PrinterSettings().PrinterName;
                        SetDefaultPrinter(printerName);
                        for (int i = 0; i < copies; i++) browser.Print();
                        SetDefaultPrinter(defaultPrinter);
                    }
                    else
                    {
                        for (int i = 0; i < copies; i++) browser.Print();
                    }
                }
                finally
                {
                    TryDelete(tempFile);
                }
            };

            browser.Navigate(new Uri(tempFile));

            var deadline = DateTime.Now.AddSeconds(30);
            while (DateTime.Now < deadline)
            {
                System.Windows.Forms.Application.DoEvents();
                System.Threading.Thread.Sleep(100);
                if (browser.ReadyState == WebBrowserReadyState.Complete)
                    break;
            }
        }
        catch
        {
            OpenInBrowser(manifest, templatePath);
        }
    }

    private static string WriteTempFile(string shipmentRef, string html)
    {
        var safe = shipmentRef.Replace("/", "-").Replace("\\", "-");
        var path = Path.Combine(Path.GetTempPath(),
            $"PeasyWare_DN_{safe}_{DateTime.Now:yyyyMMddHHmmss}.html");
        File.WriteAllText(path, html, System.Text.Encoding.UTF8);
        return path;
    }

    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    [System.Runtime.InteropServices.DllImport("winspool.drv",
        CharSet = System.Runtime.InteropServices.CharSet.Auto,
        SetLastError = true)]
    private static extern bool SetDefaultPrinter(string? printerName);
}
