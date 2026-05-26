using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Outbound;

public partial class OutstandingOrdersView : BaseView, IToolbarAware
{
    private readonly IOutboundQueryRepository   _queryRepo;
    private readonly IOutboundCommandRepository _commandRepo;
    private readonly ISkuQueryRepository        _skuRepo;
    private readonly IPartyQueryRepository      _partyRepo;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnNew;
    private ToolStripButton? _btnAllocate;
    private ToolStripButton? _btnCancelOrder;
    private ToolStripButton? _btnOrderDetails;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _filterHost;
    private TextBox? _txtSearch;
    private ComboBox? _cmbFilter;

    private List<OutboundOrderSummaryDto> _orders = new();

    public OutstandingOrdersView(
        IOutboundQueryRepository   queryRepo,
        IOutboundCommandRepository commandRepo,
        ISkuQueryRepository        skuRepo,
        IPartyQueryRepository      partyRepo)
    {
        InitializeComponent();

        _queryRepo   = queryRepo;
        _commandRepo = commandRepo;
        _skuRepo     = skuRepo;
        _partyRepo   = partyRepo;

        ConfigureGrid(dgvOrders);
        EnableDoubleBuffering(dgvOrders);

        dgvOrders.SelectionChanged += (_, _) => UpdateToolbarState();

        Load += (_, _) => LoadOrders();
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(RefreshOrders);

        _btnNew = new ToolStripButton("New order") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewOrder);

        _txtSearch = new TextBox
        {
            PlaceholderText = "Search order ref / customer / status…",
            Width = 260
        };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();

        _searchHost = new ToolStripControlHost(_txtSearch)
        {
            AutoSize = false,
            Width = 280,
            Alignment = ToolStripItemAlignment.Left
        };

        _cmbFilter = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width         = 120
        };
        _cmbFilter.Items.AddRange(["Outstanding", "Departed", "All"]);
        _cmbFilter.SelectedIndex = 0;
        _cmbFilter.SelectedIndexChanged += (_, _) => Execute(LoadOrders);

        _filterHost = new ToolStripControlHost(_cmbFilter)
        {
            AutoSize = false,
            Width    = 130
        };

        _btnAllocate = new ToolStripButton("Allocate order")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled = false
        };
        _btnAllocate.Click += Wrap(AllocateSelected);

        _btnCancelOrder = new ToolStripButton("Cancel order")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled = false
        };
        _btnCancelOrder.Click += Wrap(CancelSelected);

        _btnOrderDetails = new ToolStripButton("Order details")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled = false
        };
        _btnOrderDetails.Click += Wrap(OpenOrderDetails);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNew);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_filterHost);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnAllocate);
        toolStrip.Items.Add(_btnCancelOrder);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnOrderDetails);
    }

    private void UpdateToolbarState()
    {
        var selected = SelectedOrders();
        var count = selected.Count;

        if (_btnAllocate is not null)
        {
            var canAllocate = count == 1 &&
                (selected[0].OrderStatusCode == "NEW" ||
                 (selected[0].OrderStatusCode == "ALLOCATED" &&
                  selected[0].TotalAllocated < selected[0].TotalOrdered));
            _btnAllocate.Enabled = canAllocate;
            _btnAllocate.Text = canAllocate && selected[0].OrderStatusCode == "ALLOCATED"
                ? "Top up allocation"
                : "Allocate order";
        }

        if (_btnCancelOrder is not null)
        {
            // Only NEW orders can be cancelled; enable if all selected are NEW
            var cancellableCount = selected.Count(o => o.OrderStatusCode == "NEW");
            _btnCancelOrder.Enabled = cancellableCount > 0 && cancellableCount == count;
            _btnCancelOrder.Text = cancellableCount > 1
                ? $"Cancel order ({cancellableCount})"
                : "Cancel order";
        }

        if (_btnOrderDetails is not null)
        {
            _btnOrderDetails.Enabled = count == 1;
        }
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadOrders()
    {
        _orders = (_cmbFilter?.SelectedIndex switch
        {
            1 => _queryRepo.GetDepartedOrders(),
            2 => _queryRepo.GetAllOrders(),
            _ => _queryRepo.GetOutstandingOrders()
        }).ToList();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";

        var data = string.IsNullOrWhiteSpace(q)
            ? _orders
            : _orders.Where(o =>
                o.OrderRef.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                o.CustomerName.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                o.OrderStatusCode.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (o.DeliveryCity?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false) ||
                (o.DeliveryPostalCode?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false))
              .ToList();

        Bind(data);
    }

    private void Bind(List<OutboundOrderSummaryDto> data)
    {
        dgvOrders.DataSource = null;
        dgvOrders.DataSource = data;
    }

    private void RefreshOrders() => Execute(LoadOrders);

    // ==========================================================
    // New order
    // ==========================================================

    private void NewOrder()
    {
        using var form = new CreateOrderForm(_commandRepo, _skuRepo, _partyRepo);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        MessageBox.Show(this,
            $"Order {form.CreatedOrderRef} created successfully.",
            "Order Created",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);

        Execute(LoadOrders);
    }

    // ==========================================================
    // Allocate
    // ==========================================================

    private void AllocateSelected()
    {
        var selected = SelectedOrders();
        if (selected.Count != 1) return;

        var order = selected[0];

        if (order.OrderStatusCode != "NEW" && order.OrderStatusCode != "ALLOCATED")
        {
            MessageBox.Show(this,
                $"Order {order.OrderRef} is {order.OrderStatusCode} — cannot allocate.",
                "Allocate Order", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        var confirm = MessageBox.Show(this,
            $"Allocate order {order.OrderRef} for {order.CustomerName}?\n\nStock will be assigned automatically using the configured strategy.",
            "Confirm Allocation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button1);

        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.AllocateOrder(order.OutboundOrderId);

        // Insufficient stock — offer partial
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
                Execute(LoadOrders);
                return;
            }
        }

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Allocation Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            Execute(LoadOrders);
            return;
        }

        // Success or partial success
        var isPartial = result.ResultCode == "WARNORD01";
        var title     = isPartial ? "Partial Allocation" : "Allocation Complete";
        var msg       = isPartial
            ? $"Order {order.OrderRef} partially allocated — some lines could not be fully filled.\n\nOpen order details to review?"
            : $"Order {order.OrderRef} allocated successfully.\n\nOpen order details to review allocated stock?";

        var openDetail = MessageBox.Show(this, msg, title,
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Information,
            MessageBoxDefaultButton.Button1);

        Execute(LoadOrders);

        if (openDetail == DialogResult.Yes)
            OpenOrderDetailsFor(order.OutboundOrderId, order.OrderRef);
    }

    // ==========================================================
    // Cancel order
    // ==========================================================

    private void CancelSelected()
    {
        var eligible = SelectedOrders()
            .Where(o => o.OrderStatusCode == "NEW")
            .ToList();

        if (eligible.Count == 0) return;

        var names = eligible.Count <= 5
            ? string.Join("\n", eligible.Select(o => $"  • {o.OrderRef}  ({o.CustomerName})"))
            : $"  {eligible.Count} orders selected";

        var confirm = MessageBox.Show(this,
            $"Permanently cancel the following order(s)?\n\n{names}\n\nThis cannot be undone.",
            "Confirm Order Cancellation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var failed = new List<string>();

        foreach (var order in eligible)
        {
            var result = _commandRepo.CancelOrder(order.OutboundOrderId);
            if (!result.Success)
                failed.Add($"{order.OrderRef}: {result.FriendlyMessage}");
        }

        if (failed.Count > 0)
        {
            MessageBox.Show(this,
                $"Some orders could not be cancelled:\n\n{string.Join("\n", failed)}",
                "Cancellation Partial Failure",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }
        else
        {
            MessageBox.Show(this,
                $"{eligible.Count} order(s) cancelled.",
                "PeasyWare Outbound", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        Execute(LoadOrders);
    }

    // ==========================================================
    // Order details
    // ==========================================================

    private void OpenOrderDetails()
    {
        var selected = SelectedOrders();
        if (selected.Count != 1) return;

        OpenOrderDetailsFor(selected[0].OutboundOrderId, selected[0].OrderRef);
    }

    private void OpenOrderDetailsFor(int orderId, string orderRef)
    {
        using var form = new OrderDetailForm(orderId, orderRef, _queryRepo, _commandRepo);
        form.ShowDialog(this);
        // Refresh after closing — user may have deallocated from inside the form
        Execute(LoadOrders);
    }

    // ==========================================================
    // Helpers
    // ==========================================================

    private List<OutboundOrderSummaryDto> SelectedOrders() =>
        dgvOrders.SelectedRows
            .Cast<DataGridViewRow>()
            .Select(r => r.DataBoundItem as OutboundOrderSummaryDto)
            .Where(d => d is not null)
            .Cast<OutboundOrderSummaryDto>()
            .ToList();

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns = false;
        dgv.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect = true;
        dgv.ReadOnly = true;

        dgv.AllowUserToAddRows = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;

        dgv.RowHeadersVisible = false;
        dgv.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Clear();

        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.OrderRef),           "Order Ref",  12));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.CustomerName),         "Customer",   14));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.DeliveryAddressLine1), "Delivery",   14));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.DeliveryCity),         "City",        7));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.DeliveryPostalCode),   "Postcode",    6));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.OrderStatusCode),      "Status",      7));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.RequiredDate),         "Required",    7));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalLines),           "Lines",       3));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalOrdered),         "Ordered",     5));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalAllocated),       "Allocated",   5));
        dgv.Columns.Add(Col(nameof(OutboundOrderSummaryDto.TotalPicked),          "Picked",      5));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(OutboundOrderSummaryDto.OrderStatusCode)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "NEW" => Color.DimGray,
                "ALLOCATED" => Color.DarkBlue,
                "PICKING" => Color.DarkOrange,
                "PICKED" => Color.DarkGreen,
                _ => Color.Black
            };
        };
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill) =>
        new DataGridViewTextBoxColumn
        {
            DataPropertyName = prop,
            HeaderText = header,
            FillWeight = fill
        };

    private static void EnableDoubleBuffering(DataGridView dgv)
    {
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
    }
}
