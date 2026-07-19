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
    private Button _btnAllocate = null!;
    private Button _btnAllocateAll = null!;
    private List<OutboundOrderSummaryDto> _orders = new();

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

        _dgvOrders.SelectionChanged += (_, _) => UpdateActionButtons();

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

        var btnAddOrder = new Button
        {
            Text     = "Add order",
            Width    = 90,
            Height   = 28,
            Location = new Point(126, 7)
        };
        btnAddOrder.Click += (_, _) => AddOrder();

        _btnAllocate = new Button
        {
            Text     = "Allocate",
            Width    = 100,
            Height   = 28,
            Location = new Point(224, 7),
            Enabled  = false
        };
        _btnAllocate.Click += (_, _) => AllocateSelected();

        _btnAllocateAll = new Button
        {
            Text     = "Allocate all",
            Width    = 110,
            Height   = 28,
            Location = new Point(332, 7),
            Enabled  = false
        };
        _btnAllocateAll.Click += (_, _) => AllocateAll();

        var btnPrintManifest = new Button
        {
            Text     = "Print manifest",
            Width    = 110,
            Height   = 28,
            Location = new Point(450, 7)
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

        pnlFooter.Controls.AddRange([btnOrderDetail, btnAddOrder, _btnAllocate, _btnAllocateAll, btnPrintManifest, btnClose]);

        Controls.Add(_dgvOrders);
        Controls.Add(pnlFooter);
        Controls.Add(lblTitle);

        EnableDoubleBuffering(_dgvOrders);
        CancelButton = btnClose;
    }

    private void LoadOrders()
    {
        _orders = _queryRepo.GetOrdersOnShipment(_shipmentId).ToList();
        _dgvOrders.DataSource = null;
        _dgvOrders.DataSource = _orders;
        UpdateActionButtons();
    }

    private void UpdateActionButtons()
    {
        var selected = SelectedOrder();

        var canAllocateSelected = selected is not null &&
            (selected.OrderStatusCode == "NEW" ||
             (selected.OrderStatusCode == "ALLOCATED" && selected.TotalAllocated < selected.TotalOrdered));

        _btnAllocate.Enabled = canAllocateSelected;
        _btnAllocate.Text = canAllocateSelected && selected!.OrderStatusCode == "ALLOCATED"
            ? "Top up"
            : "Allocate";

        var unallocatedCount = _orders.Count(o => o.OrderStatusCode == "NEW");
        _btnAllocateAll.Enabled = unallocatedCount > 0;
        _btnAllocateAll.Text = unallocatedCount > 1
            ? $"Allocate all ({unallocatedCount})"
            : "Allocate all";
    }

    private OutboundOrderSummaryDto? SelectedOrder() =>
        _dgvOrders.SelectedRows.Count == 1
            ? _dgvOrders.SelectedRows[0].DataBoundItem as OutboundOrderSummaryDto
            : null;

    // ── Allocate selected order (same flow as Outstanding Orders: confirm,
    //    offer partial on insufficient stock, refresh) ──
    private void AllocateSelected()
    {
        var order = SelectedOrder();
        if (order is null) return;

        var confirm = MessageBox.Show(this,
            $"Allocate order {order.OrderRef} for {order.CustomerName}?\n\nStock will be assigned automatically using the configured strategy.",
            "Confirm Allocation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button1);

        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.AllocateOrder(order.OutboundOrderId);

        if (!result.Success && result.ResultCode is "ERRALLOC01" or "ERRALLOC02")
        {
            var offerPartial = MessageBox.Show(this,
                $"Insufficient stock to fully allocate {order.OrderRef}.\n\nAllocate whatever stock is currently available (partial allocation)?",
                "Partial Allocation",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);

            if (offerPartial == DialogResult.Yes)
                result = _commandRepo.AllocateOrder(order.OutboundOrderId, allowPartial: true);
            else
            {
                LoadOrders();
                return;
            }
        }

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Allocation Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            LoadOrders();
            return;
        }

        var isPartial = result.ResultCode == "WARNORD01";
        MessageBox.Show(this,
            isPartial
                ? $"Order {order.OrderRef} partially allocated — some lines could not be fully filled."
                : $"Order {order.OrderRef} allocated successfully.",
            isPartial ? "Partial Allocation" : "Allocation Complete",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);

        LoadOrders();
    }

    // ── Allocate every unallocated (NEW) order on this shipment in one pass -
    //    the point being nobody has to leave this screen with a shipment
    //    that still has orphaned, never-allocated orders sitting on it.
    //    No inline partial-allocation prompting here (that's a per-order
    //    judgement call, made via the single Allocate button); this just
    //    reports what happened for each one. ──
    private void AllocateAll()
    {
        var pending = _orders.Where(o => o.OrderStatusCode == "NEW").ToList();
        if (pending.Count == 0) return;

        var confirm = MessageBox.Show(this,
            $"Allocate all {pending.Count} unallocated order(s) on shipment {_shipmentRef}?\n\n" +
            string.Join("\n", pending.Select(o => $"  • {o.OrderRef}  ({o.CustomerName})")),
            "Confirm Bulk Allocation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button1);

        if (confirm != DialogResult.Yes) return;

        var succeeded = new List<string>();
        var partial   = new List<string>();
        var failed    = new List<string>();

        foreach (var order in pending)
        {
            var result = _commandRepo.AllocateOrder(order.OutboundOrderId);

            if (result.Success && result.ResultCode == "WARNORD01")
                partial.Add(order.OrderRef);
            else if (result.Success)
                succeeded.Add(order.OrderRef);
            else
                failed.Add($"{order.OrderRef}: {result.FriendlyMessage}");
        }

        var summary = new List<string>();
        if (succeeded.Count > 0) summary.Add($"Allocated: {string.Join(", ", succeeded)}");
        if (partial.Count   > 0) summary.Add($"Partially allocated (insufficient stock): {string.Join(", ", partial)}");
        if (failed.Count    > 0) summary.Add($"Failed:\n{string.Join("\n", failed)}");

        MessageBox.Show(this,
            string.Join("\n\n", summary),
            failed.Count > 0 ? "Bulk Allocation — Some Failed" : "Bulk Allocation Complete",
            MessageBoxButtons.OK,
            failed.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);

        LoadOrders();
    }

    private void AddOrder()
    {
        using var form = new AddOrderToShipmentForm(
            _shipmentRef,
            _queryRepo,
            _commandRepo);

        if (form.ShowDialog(this) != DialogResult.OK) return;
        LoadOrders();
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
