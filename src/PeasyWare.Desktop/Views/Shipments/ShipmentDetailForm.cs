using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Services;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Services;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Shipments;

public sealed class ShipmentDetailForm : Form
{
    private readonly int                        _shipmentId;
    private readonly string                     _shipmentRef;
    private readonly IOutboundQueryRepository   _queryRepo;
    private readonly IOutboundCommandRepository _commandRepo;
    private readonly IShipmentManifestRepository _manifestRepo;
    private readonly ISettingsQueryRepository   _settingsRepo;

    private DataGridView _dgvOrders = null!;

    public ShipmentDetailForm(
        int                         shipmentId,
        string                      shipmentRef,
        IOutboundQueryRepository    queryRepo,
        IOutboundCommandRepository  commandRepo,
        IShipmentManifestRepository manifestRepo,
        ISettingsQueryRepository    settingsRepo)
    {
        _shipmentId   = shipmentId;
        _shipmentRef  = shipmentRef;
        _queryRepo    = queryRepo;
        _commandRepo  = commandRepo;
        _manifestRepo = manifestRepo;
        _settingsRepo = settingsRepo;

        BuildUi();
        Load += (_, _) => LoadOrders();
    }

    private void BuildUi()
    {
        Text            = $"Shipment — {_shipmentRef}";
        Size            = new Size(1100, 480);
        MinimumSize     = new Size(800, 380);
        StartPosition   = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.Sizable;

        // Title bar
        var lblTitle = new Label
        {
            Text      = $"Orders on shipment  {_shipmentRef}",
            Dock      = DockStyle.Top,
            Height    = 32,
            Padding   = new Padding(8, 8, 0, 0),
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            BackColor = Color.FromArgb(45, 45, 48),
            ForeColor = Color.White
        };

        // Grid
        _dgvOrders = new DataGridView
        {
            Dock                  = DockStyle.Fill,
            AutoGenerateColumns   = false,
            SelectionMode         = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect           = false,
            ReadOnly              = true,
            AllowUserToAddRows    = false,
            AllowUserToDeleteRows = false,
            AllowUserToResizeRows = false,
            RowHeadersVisible     = false,
            AutoSizeColumnsMode   = DataGridViewAutoSizeColumnsMode.Fill,
            EnableHeadersVisualStyles = false,
            BackgroundColor       = SystemColors.Window,
            BorderStyle           = BorderStyle.None
        };

        _dgvOrders.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        _dgvOrders.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        _dgvOrders.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        _dgvOrders.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        _dgvOrders.ColumnHeadersDefaultCellStyle.Font               = new Font(_dgvOrders.Font, FontStyle.Bold);
        _dgvOrders.DefaultCellStyle.SelectionBackColor              = Color.LightSteelBlue;
        _dgvOrders.DefaultCellStyle.SelectionForeColor              = Color.Black;

        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.OrderRef),           "Order Ref",  12));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.CustomerName),        "Customer",   16));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.DeliveryAddressLine1),"Delivery",   16));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.DeliveryCity),        "City",        8));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.DeliveryPostalCode),  "Postcode",    6));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.OrderStatusCode),     "Status",      7));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.RequiredDate),        "Required",    7));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalLines),          "Lines",       3));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalOrdered),        "Ordered",     5));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalAllocated),      "Allocated",   5));
        _dgvOrders.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalPicked),         "Picked",      5));

        _dgvOrders.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (_dgvOrders.Columns[e.ColumnIndex].DataPropertyName
                != nameof(OutboundOrderSummaryDto.OrderStatusCode)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "NEW"       => Color.DimGray,
                "ALLOCATED" => Color.DarkBlue,
                "PICKING"   => Color.DarkOrange,
                "PICKED"    => Color.DarkGreen,
                "LOADED"    => Color.DarkBlue,
                "SHIPPED"   => Color.SeaGreen,
                _           => Color.Black
            };
        };

        // Double-click opens order detail
        _dgvOrders.CellDoubleClick += (_, e) =>
        {
            if (e.RowIndex < 0) return;
            OpenOrderDetail();
        };

        // Footer
        var pnlFooter = new Panel
        {
            Dock   = DockStyle.Bottom,
            Height = 42,
            Padding = new Padding(8, 6, 8, 6)
        };

        var btnOrderDetail = new Button
        {
            Text     = "Order details",
            Width    = 110,
            Height   = 28,
            Location = new Point(8, 7)
        };
        btnOrderDetail.Click += (_, _) => OpenOrderDetail();

        var btnPrintManifest = new Button
        {
            Text     = "Print manifest",
            Width    = 110,
            Height   = 28,
            Location = new Point(126, 7)
        };
        btnPrintManifest.Click += (_, _) => PrintManifest();

        var btnClose = new Button
        {
            Text        = "Close",
            Width       = 80,
            Height      = 28,
            DialogResult = DialogResult.Cancel
        };
        btnClose.Location = new Point(pnlFooter.Width - 96, 7);
        btnClose.Anchor   = AnchorStyles.Right | AnchorStyles.Top;

        pnlFooter.Controls.AddRange([btnOrderDetail, btnPrintManifest, btnClose]);

        Controls.Add(_dgvOrders);
        Controls.Add(pnlFooter);
        Controls.Add(lblTitle);

        EnableDoubleBuffering(_dgvOrders);
        CancelButton = btnClose;
    }

    private void LoadOrders()
    {
        var orders = _queryRepo.GetOrdersOnShipment(_shipmentId).ToList();
        _dgvOrders.DataSource = null;
        _dgvOrders.DataSource = orders;
    }

    private void PrintManifest()
    {
        var manifest = _manifestRepo.GetManifest(_shipmentRef);

        if (manifest is null || manifest.Lines.Count == 0)
        {
            MessageBox.Show(this,
                $"No shipped units found for {_shipmentRef}.\n\nThe shipment may not have departed yet.",
                "No manifest data",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }

        // Check auto-print setting
        var settings       = _settingsRepo.GetSettings();
        var autoPrint      = settings.FirstOrDefault(s => s.SettingName == "printing.auto_print_delivery_note")?.SettingValue == "true";
        var printerName    = settings.FirstOrDefault(s => s.SettingName == "printing.delivery_note_printer")?.SettingValue ?? "";
        var copiesStr      = settings.FirstOrDefault(s => s.SettingName == "printing.delivery_note_copies")?.SettingValue ?? "2";
        var copies         = int.TryParse(copiesStr, out var c) ? c : 2;

        if (autoPrint && !string.IsNullOrWhiteSpace(printerName))
        {
            DeliveryNotePrinter.PrintSilent(manifest, printerName, copies);
            MessageBox.Show(this,
                $"Delivery note sent to printer: {printerName} ({copies} cop{(copies == 1 ? "y" : "ies")}).",
                "Printed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        else
        {
            // Browser fallback
            DeliveryNotePrinter.OpenInBrowser(manifest);
        }
    }

    private void OpenOrderDetail()
    {
        if (_dgvOrders.SelectedRows.Count == 0) return;
        if (_dgvOrders.SelectedRows[0].DataBoundItem is not OutboundOrderSummaryDto order) return;

        using var form = new Outbound.OrderDetailForm(
            order.OutboundOrderId,
            order.OrderRef,
            _queryRepo,
            _commandRepo);
        form.ShowDialog(this);
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill };

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
