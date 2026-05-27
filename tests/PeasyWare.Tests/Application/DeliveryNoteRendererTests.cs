using PeasyWare.Application.Dto;
using PeasyWare.Application.Services;
using System;
using System.Collections.Generic;
using Xunit;

namespace PeasyWare.Tests.Application;

public class DeliveryNoteRendererTests
{
    // ==========================================================
    // Helpers
    // ==========================================================

    private static ShipmentManifestDto SimpleManifest(
        string shipmentRef    = "SHIP-2026-001",
        string customerName   = "Hop & Barrel",
        string haulierName    = "Swift Freight",
        string vehicleRef     = "AB12 CDE",
        DateTime? departure   = null,
        IReadOnlyList<ShipmentManifestLineDto>? lines = null) =>
        new()
        {
            ShipmentRef    = shipmentRef,
            ShipmentStatus = "DEPARTED",
            CustomerName   = customerName,
            HaulierName    = haulierName,
            VehicleRef     = vehicleRef,
            ActualDeparture = departure ?? new DateTime(2026, 5, 23, 7, 39, 0),
            DeliveryLine1  = "45 High Street",
            DeliveryCity   = "Manchester",
            DeliveryPostalCode = "M1 2AB",
            TotalPallets   = lines?.Count ?? 1,
            TotalUnits     = 60,
            TotalWeightKg  = 864.00m,
            Lines          = lines ?? new List<ShipmentManifestLineDto>
            {
                new()
                {
                    Sscc           = "340100000000000011",
                    SkuCode        = "PWS-001",
                    SkuDescription = "Pale Ale 500ml 24x1",
                    BatchNumber    = "B-PA-260601",
                    BestBefore     = "01/12/2026",
                    Quantity       = 60,
                    UomCode        = "Case",
                    TotalWeightKg  = 864.00m,
                    OrderRef       = "ORD-2026-001"
                }
            }
        };

    private static string Render(ShipmentManifestDto? manifest = null) =>
        DeliveryNoteRenderer.Render(manifest ?? SimpleManifest());

    // ==========================================================
    // Placeholder replacement
    // ==========================================================

    [Fact]
    public void Render_ContainsShipmentRef()
    {
        var html = Render();
        Assert.Contains("SHIP-2026-001", html);
    }

    [Fact]
    public void Render_ContainsCustomerName()
    {
        var html = Render();
        // CustomerName is placed raw into the template — not HTML-escaped at header level
        Assert.Contains("Hop & Barrel", html);
    }

    [Fact]
    public void Render_ContainsHaulierName()
    {
        var html = Render();
        Assert.Contains("Swift Freight", html);
    }

    [Fact]
    public void Render_ContainsVehicleRef()
    {
        var html = Render();
        Assert.Contains("AB12 CDE", html);
    }

    [Fact]
    public void Render_ContainsDepartureDate()
    {
        var html = Render();
        Assert.Contains("23/05/2026", html);
    }

    [Fact]
    public void Render_ContainsDepartureTime()
    {
        var html = Render();
        Assert.Contains("07:39", html);
    }

    [Fact]
    public void Render_ContainsTotalPallets()
    {
        var html = Render();
        Assert.Contains("1", html);
    }

    [Fact]
    public void Render_ContainsTotalUnits()
    {
        var html = Render();
        Assert.Contains("60", html);
    }

    [Fact]
    public void Render_ContainsGrossWeight()
    {
        var html = Render();
        Assert.Contains("864.00 kg", html);
    }

    [Fact]
    public void Render_NoUnreplacedPlaceholders()
    {
        var html = Render();
        Assert.DoesNotContain("{{", html);
        Assert.DoesNotContain("}}", html);
    }

    // ==========================================================
    // Null / missing fields
    // ==========================================================

    [Fact]
    public void Render_NullCustomerName_ShowsUnknown()
    {
        var manifest = SimpleManifest(customerName: null!);
        var html = DeliveryNoteRenderer.Render(manifest);
        Assert.Contains("(unknown)", html);
    }

    [Fact]
    public void Render_NullHaulierName_ShowsUnknown()
    {
        var manifest = SimpleManifest(haulierName: null!);
        var html = DeliveryNoteRenderer.Render(manifest);
        Assert.Contains("(unknown)", html);
    }

    [Fact]
    public void Render_NullVehicleRef_ShowsUnknown()
    {
        var manifest = SimpleManifest(vehicleRef: null!);
        var html = DeliveryNoteRenderer.Render(manifest);
        Assert.Contains("(unknown)", html);
    }

    [Fact]
    public void Render_NullDeparture_ShowsDash()
    {
        var noDepart = new ShipmentManifestDto
        {
            ShipmentRef     = "SHIP-TEST",
            CustomerName    = "Test",
            HaulierName     = "Test Haulier",
            VehicleRef      = "XX00 XXX",
            ActualDeparture = null,
            TotalPallets    = 0,
            TotalUnits      = 0,
            TotalWeightKg   = 0,
            Lines           = new List<ShipmentManifestLineDto>()
        };
        var html = DeliveryNoteRenderer.Render(noDepart);
        Assert.Contains("—", html);
        Assert.DoesNotContain("{{DEPARTURE_DATE}}", html);
    }

    // ==========================================================
    // Address building
    // ==========================================================

    [Fact]
    public void Render_FullAddress_AllPartsJoined()
    {
        var html = Render();
        Assert.Contains("45 High Street, Manchester, M1 2AB", html);
    }

    [Fact]
    public void Render_PartialAddress_SkipsNulls()
    {
        var manifest = new ShipmentManifestDto
        {
            ShipmentRef     = "SHIP-TEST",
            CustomerName    = "Test Customer",
            HaulierName     = "Test Haulier",
            VehicleRef      = "XX00 XXX",
            DeliveryLine1   = null,
            DeliveryCity    = "Leeds",
            DeliveryPostalCode = null,
            ActualDeparture = DateTime.Now,
            TotalPallets    = 0,
            TotalUnits      = 0,
            TotalWeightKg   = 0,
            Lines           = new List<ShipmentManifestLineDto>()
        };
        var html = DeliveryNoteRenderer.Render(manifest);
        Assert.Contains("Leeds", html);
        Assert.DoesNotContain(", Leeds,", html);  // no leading or trailing commas
        Assert.DoesNotContain("Leeds,", html);
    }

    // ==========================================================
    // Lines rendering
    // ==========================================================

    [Fact]
    public void Render_LineContainsSscc()
    {
        var html = Render();
        Assert.Contains("340100000000000011", html);
    }

    [Fact]
    public void Render_LineContainsSkuCode()
    {
        var html = Render();
        Assert.Contains("PWS-001", html);
    }

    [Fact]
    public void Render_LineContainsBatch()
    {
        var html = Render();
        Assert.Contains("B-PA-260601", html);
    }

    [Fact]
    public void Render_LineContainsOrderRef()
    {
        var html = Render();
        Assert.Contains("ORD-2026-001", html);
    }

    [Fact]
    public void Render_LineContainsWeight()
    {
        var html = Render();
        Assert.Contains("864.00", html);
    }

    [Fact]
    public void Render_MultipleLines_AllRendered()
    {
        var lines = new List<ShipmentManifestLineDto>
        {
            new() { Sscc = "340100000000000011", SkuCode = "PWS-001", SkuDescription = "Pale Ale",  Quantity = 60, TotalWeightKg = 864m, OrderRef = "ORD-001" },
            new() { Sscc = "340100000000000021", SkuCode = "PWS-002", SkuDescription = "Lager",     Quantity = 80, TotalWeightKg = 768m, OrderRef = "ORD-001" },
            new() { Sscc = "340100000000000031", SkuCode = "PWS-003", SkuDescription = "Stout",     Quantity = 60, TotalWeightKg = 768m, OrderRef = "ORD-002" },
        };
        var manifest = SimpleManifest(lines: lines);
        var html = DeliveryNoteRenderer.Render(manifest);

        Assert.Contains("340100000000000011", html);
        Assert.Contains("340100000000000021", html);
        Assert.Contains("340100000000000031", html);
    }

    [Fact]
    public void Render_EmptyLines_NoTableRows()
    {
        var manifest = SimpleManifest(lines: new List<ShipmentManifestLineDto>());
        var html = DeliveryNoteRenderer.Render(manifest);
        // <thead><tr> will always exist — check no data cells were rendered
        Assert.DoesNotContain("<td", html);
    }

    // ==========================================================
    // HTML escaping
    // ==========================================================

    [Fact]
    public void Render_HtmlSpecialCharsInSscc_AreEscaped()
    {
        var lines = new List<ShipmentManifestLineDto>
        {
            new()
            {
                Sscc           = "<script>alert('xss')</script>",
                SkuCode        = "PWS-001",
                SkuDescription = "Test",
                Quantity       = 1
            }
        };
        var manifest = SimpleManifest(lines: lines);
        var html = DeliveryNoteRenderer.Render(manifest);

        Assert.DoesNotContain("<script>", html);
        Assert.Contains("&lt;script&gt;", html);
    }

    [Fact]
    public void Render_AmpersandInDescription_IsEscaped()
    {
        var lines = new List<ShipmentManifestLineDto>
        {
            new()
            {
                Sscc           = "340100000000000011",
                SkuCode        = "PWS-001",
                SkuDescription = "Ale & Lager Mix",
                Quantity       = 1
            }
        };
        var manifest = SimpleManifest(lines: lines);
        var html = DeliveryNoteRenderer.Render(manifest);

        Assert.Contains("Ale &amp; Lager Mix", html);
        Assert.DoesNotContain("Ale & Lager Mix", html);
    }

    // ==========================================================
    // Fallback template
    // ==========================================================

    [Fact]
    public void Render_NonExistentTemplatePath_UsesFallback()
    {
        var html = DeliveryNoteRenderer.Render(SimpleManifest(), templatePath: "C:/does/not/exist.html");
        // Should still render — fallback template is used
        Assert.Contains("SHIP-2026-001", html);
        Assert.Contains("DELIVERY NOTE", html);
        Assert.DoesNotContain("{{", html);
    }

    [Fact]
    public void Render_ExplicitTemplatePath_UsesIt()
    {
        // Write a minimal custom template to a temp file
        var tempPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "pw_test_template.html");
        System.IO.File.WriteAllText(tempPath, "<html>CUSTOM:{{SHIPMENT_REF}}</html>");

        try
        {
            var html = DeliveryNoteRenderer.Render(SimpleManifest(), templatePath: tempPath);
            Assert.StartsWith("<html>CUSTOM:SHIP-2026-001</html>", html.Trim());
        }
        finally
        {
            System.IO.File.Delete(tempPath);
        }
    }
}
