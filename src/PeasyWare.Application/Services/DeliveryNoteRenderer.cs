using PeasyWare.Application.Dto;
using System;
using System.Linq;
using System.Text;

namespace PeasyWare.Application.Services;

/// <summary>
/// Renders a ShipmentManifestDto into an HTML delivery note.
/// Template is read from the path provided (default: Database/Templates/delivery_note.html).
/// Falls back to embedded minimal template if file not found.
/// </summary>
public static class DeliveryNoteRenderer
{
    public static string Render(ShipmentManifestDto manifest, string? templatePath = null)
    {
        var template = LoadTemplate(templatePath);

        var address = BuildAddress(manifest);
        var departure = manifest.ActualDeparture;

        var html = template
            .Replace("{{SHIPMENT_REF}}",   manifest.ShipmentRef)
            .Replace("{{CUSTOMER_NAME}}",  manifest.CustomerName ?? "(unknown)")
            .Replace("{{DELIVERY_ADDRESS}}",address)
            .Replace("{{HAULIER_NAME}}",   manifest.HaulierName  ?? "(unknown)")
            .Replace("{{VEHICLE_REF}}",    manifest.VehicleRef   ?? "(unknown)")
            .Replace("{{DEPARTURE_DATE}}", departure.HasValue ? departure.Value.ToString("dd/MM/yyyy") : "—")
            .Replace("{{DEPARTURE_TIME}}", departure.HasValue ? departure.Value.ToString("HH:mm")     : "")
            .Replace("{{TOTAL_PALLETS}}",  manifest.TotalPallets.ToString())
            .Replace("{{TOTAL_UNITS}}",    manifest.TotalUnits.ToString())
            .Replace("{{TOTAL_WEIGHT}}",   manifest.TotalWeightKg.ToString("N2") + " kg")
            .Replace("{{GENERATED_AT}}",   DateTime.Now.ToString("dd/MM/yyyy HH:mm"))
            .Replace("{{LINES}}",          BuildLines(manifest));

        return html;
    }

    private static string BuildLines(ShipmentManifestDto manifest)
    {
        var sb = new StringBuilder();
        string? currentOrder  = null;
        int     groupPallets  = 0;
        int     groupUnits    = 0;
        decimal groupWeight   = 0m;

        void FlushSubtotal()
        {
            if (currentOrder is null) return;
            sb.AppendLine($"""
                <tr class="order-subtotal">
                  <td colspan="5">Order subtotal &mdash; {Esc(currentOrder)}</td>
                  <td class="right">{groupUnits}</td>
                  <td></td>
                  <td class="right">{groupWeight:N2} kg</td>
                  <td>{groupPallets} pallet{(groupPallets == 1 ? "" : "s")}</td>
                </tr>
                """);
            groupPallets = 0; groupUnits = 0; groupWeight = 0m;
        }

        foreach (var line in manifest.Lines)
        {
            var order = line.OrderRef ?? "";
            if (order != currentOrder)
            {
                FlushSubtotal();
                currentOrder = order;
            }

            groupPallets++;
            groupUnits  += line.Quantity;
            groupWeight += line.TotalWeightKg ?? 0m;

            sb.AppendLine($"""
                <tr>
                  <td class="mono">{Esc(line.Sscc)}</td>
                  <td>{Esc(line.SkuCode)}</td>
                  <td>{Esc(line.SkuDescription)}</td>
                  <td>{Esc(line.BatchNumber)}</td>
                  <td>{Esc(line.BestBefore)}</td>
                  <td class="right">{line.Quantity}</td>
                  <td>{Esc(line.UomCode)}</td>
                  <td class="right">{(line.TotalWeightKg.HasValue ? line.TotalWeightKg.Value.ToString("N2") : "")} kg</td>
                  <td>{Esc(line.OrderRef)}</td>
                </tr>
                """);
        }

        FlushSubtotal();  // last group
        return sb.ToString();
    }

    private static string BuildAddress(ShipmentManifestDto m)
    {
        var parts = new[] { m.DeliveryLine1, m.DeliveryCity, m.DeliveryPostalCode }
            .Where(p => !string.IsNullOrWhiteSpace(p));
        return string.Join(", ", parts);
    }

    private static string LoadTemplate(string? path)
    {
        // Explicit path given but file not found → use MinimalTemplate immediately.
        // The directory search only applies when no explicit path was provided.
        if (path is not null)
            return System.IO.File.Exists(path)
                ? System.IO.File.ReadAllText(path)
                : MinimalTemplate();

        // No explicit path — search from BaseDirectory / current dir upward
        foreach (var startDir in new[] { AppContext.BaseDirectory, System.IO.Directory.GetCurrentDirectory() })
        {
            var dir = startDir;
            for (int i = 0; i < 8; i++)
            {
                var candidate = System.IO.Path.Combine(dir, "Database", "Templates", "delivery_note.html");
                if (System.IO.File.Exists(candidate))
                    return System.IO.File.ReadAllText(candidate);
                var parent = System.IO.Directory.GetParent(dir);
                if (parent is null) break;
                dir = parent.FullName;
            }
        }

        return MinimalTemplate();
    }

    private static string MinimalTemplate() => """
        <!DOCTYPE html><html><head><meta charset="UTF-8">
        <title>Delivery Note — {{SHIPMENT_REF}}</title>
        <style>body{font-family:Arial;font-size:10pt;padding:15mm}
        h1{font-size:16pt}table{width:100%;border-collapse:collapse}
        th{background:#1a1a2e;color:#fff;padding:4px 6px;text-align:left}
        td{padding:3px 6px;border-bottom:1px solid #eee}.right{text-align:right}</style>
        </head><body>
        <h1>DELIVERY NOTE — {{SHIPMENT_REF}}</h1>
        <p><strong>Customer:</strong> {{CUSTOMER_NAME}}&nbsp;&nbsp;
        <strong>Deliver to:</strong> {{DELIVERY_ADDRESS}}&nbsp;&nbsp;
        <strong>Haulier:</strong> {{HAULIER_NAME}}&nbsp;&nbsp;
        <strong>Vehicle:</strong> {{VEHICLE_REF}}&nbsp;&nbsp;
        <strong>Departed:</strong> {{DEPARTURE_DATE}} {{DEPARTURE_TIME}}</p>
        <table><thead><tr><th>SSCC</th><th>SKU</th><th>Description</th>
        <th>Batch</th><th>BBE</th><th class="right">Qty</th><th>UOM</th><th class="right">Weight</th><th>Order</th>
        </tr></thead><tbody>{{LINES}}</tbody></table>
        <p><strong>Total pallets: {{TOTAL_PALLETS}} &nbsp;|&nbsp; Total units: {{TOTAL_UNITS}} &nbsp;|&nbsp; Gross weight: {{TOTAL_WEIGHT}}</strong></p>
        <p style="font-size:8pt;color:#999;margin-top:10mm">Generated {{GENERATED_AT}}</p>
        </body></html>
        """;

    private static string Esc(string? s) =>
        string.IsNullOrEmpty(s) ? "" :
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");
}
