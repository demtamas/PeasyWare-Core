using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Outbound;

public sealed class OrderDetailForm : Form
{
    private readonly int _outboundOrderId;
    private readonly IOutboundQueryRepository _queryRepo;
    private readonly IOutboundCommandRepository _commandRepo;

    // ── Controls ─────────────────────────────────────────────────────────

    private TabControl _tabs = null!;
    private TabPage _tabLines = null!;
    private TabPage _tabAllocs = null!;

    private DataGridView _dgvLines = null!;
    private DataGridView _dgvAllocs = null!;

    private Button _btnDeallocateSelected = null!;
    private Button _btnClose = null!;

    // ── State ─────────────────────────────────────────────────────────────

    private List<OutboundOrderLineDto> _lines = new();
    private List<OutboundAllocationDto> _allocs = new();

    // ─────────────────────────────────────────────────────────────────────

    public OrderDetailForm(
        int outboundOrderId,
        string orderRef,
        IOutboundQueryRepository queryRepo,
        IOutboundCommandRepository commandRepo)
    {
        _outboundOrderId = outboundOrderId;
        _queryRepo = queryRepo;
        _commandRepo = commandRepo;

        BuildForm(orderRef);

        Load += (_, _) =>
        {
            LoadLines();
            LoadAllocations();
        };
    }

    // ═════════════════════════════════════════════════════════════════════
    // Form construction
    // ═════════════════════════════════════════════════════════════════════

    private void BuildForm(string orderRef)
    {
        Text = $"Order details — {orderRef}";
        Size = new Size(1000, 620);
        MinimumSize = new Size(800, 500);
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.Sizable;
        ShowInTaskbar = false;

        // ── Tab control ──────────────────────────────────────────────────

        _tabs = new TabControl { Dock = DockStyle.Fill };

        // Lines tab
        _tabLines = new TabPage("Order lines");
        _dgvLines = BuildGrid();
        ConfigureLinesGrid(_dgvLines);
        _tabLines.Controls.Add(_dgvLines);

        // Allocations tab
        _tabAllocs = new TabPage("Allocated stock");
        BuildAllocationsTab();

        _tabs.TabPages.Add(_tabLines);
        _tabs.TabPages.Add(_tabAllocs);
        _tabs.SelectedIndexChanged += (_, _) => UpdateDeallocateButton();

        // ── Bottom strip ─────────────────────────────────────────────────

        var bottomPanel = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 44,
            Padding = new Padding(8, 6, 8, 6)
        };

        _btnDeallocateSelected = new Button
        {
            Text = "Deallocate selected",
            Width = 160,
            Height = 30,
            Enabled = false,
            Anchor = AnchorStyles.Left | AnchorStyles.Bottom
        };
        _btnDeallocateSelected.Click += BtnDeallocateSelected_Click;

        _btnClose = new Button
        {
            Text = "Close",
            Width = 80,
            Height = 30,
            DialogResult = DialogResult.Cancel,
            Anchor = AnchorStyles.Right | AnchorStyles.Bottom
        };
        _btnClose.Location = new Point(bottomPanel.Width - 96, 7);
        _btnClose.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;

        bottomPanel.Controls.Add(_btnDeallocateSelected);
        bottomPanel.Controls.Add(_btnClose);

        // ── Separator line ───────────────────────────────────────────────

        var separator = new Panel
        {
            Dock = DockStyle.Bottom,
            Height = 1,
            BackColor = SystemColors.ControlDark
        };

        Controls.Add(_tabs);
        Controls.Add(separator);
        Controls.Add(bottomPanel);

        AcceptButton = _btnClose;
        CancelButton = _btnClose;
    }

    private void BuildAllocationsTab()
    {
        _dgvAllocs = BuildGrid();
        ConfigureAllocationsGrid(_dgvAllocs);
        _dgvAllocs.SelectionChanged += (_, _) => UpdateDeallocateButton();
        _dgvAllocs.Dock = DockStyle.Fill;
        _tabAllocs.Controls.Add(_dgvAllocs);
    }

    // ═════════════════════════════════════════════════════════════════════
    // Data loading
    // ═════════════════════════════════════════════════════════════════════

    private void LoadLines()
    {
        try
        {
            _lines = _queryRepo.GetOrderLines(_outboundOrderId).ToList();
            _dgvLines.DataSource = null;
            _dgvLines.DataSource = _lines;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Error loading order lines",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void LoadAllocations()
    {
        try
        {
            _allocs = _queryRepo.GetAllocationsForOrder(_outboundOrderId)
                .Where(a => a.AllocationStatus != "CANCELLED")
                .ToList();

            _dgvAllocs.DataSource = null;
            _dgvAllocs.DataSource = _allocs;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Error loading allocations",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }

        UpdateDeallocateButton();
    }

    // ═════════════════════════════════════════════════════════════════════
    // Deallocate selected rows (Allocations tab only)
    // ═════════════════════════════════════════════════════════════════════

    private void UpdateDeallocateButton()
    {
        if (_btnDeallocateSelected is null) return;

        var onAllocsTab = _tabs.SelectedTab == _tabAllocs;

        if (!onAllocsTab)
        {
            _btnDeallocateSelected.Enabled = false;
            return;
        }

        var eligible = SelectedAllocations()
            .Count(a => a.AllocationStatus == "PENDING" || a.AllocationStatus == "CONFIRMED");

        _btnDeallocateSelected.Enabled = eligible > 0;
        _btnDeallocateSelected.Text = eligible > 1
            ? $"Deallocate selected ({eligible})"
            : "Deallocate selected";
    }

    private void BtnDeallocateSelected_Click(object? sender, EventArgs e)
    {
        var eligible = SelectedAllocations()
            .Where(a => a.AllocationStatus == "PENDING" || a.AllocationStatus == "CONFIRMED")
            .ToList();

        if (eligible.Count == 0) return;

        var names = eligible.Count <= 8
            ? string.Join("\n", eligible.Select(a => $"  • {a.Sscc}  ({a.SkuCode})"))
            : $"  {eligible.Count} units selected";

        var confirm = MessageBox.Show(this,
            $"Cancel the following allocation(s)?\n\n{names}\n\nStock will be released back to available.",
            "Confirm Deallocation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var failed = new List<string>();

        foreach (var alloc in eligible)
        {
            var result = _commandRepo.CancelAllocation(
                alloc.AllocationId,
                "Deallocated via Order detail form");

            if (!result.Success)
                failed.Add($"{alloc.Sscc}: {result.FriendlyMessage}");
        }

        if (failed.Count > 0)
        {
            MessageBox.Show(this,
                $"Some allocations could not be cancelled:\n\n{string.Join("\n", failed)}",
                "Partial Failure",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }

        // Refresh both tabs — line qtys change too
        LoadLines();
        LoadAllocations();
    }

    private List<OutboundAllocationDto> SelectedAllocations() =>
        _dgvAllocs.SelectedRows
            .Cast<DataGridViewRow>()
            .Select(r => r.DataBoundItem as OutboundAllocationDto)
            .Where(d => d is not null)
            .Cast<OutboundAllocationDto>()
            .ToList();

    // ═════════════════════════════════════════════════════════════════════
    // Grid configuration
    // ═════════════════════════════════════════════════════════════════════

    private static DataGridView BuildGrid()
    {
        var dgv = new DataGridView
        {
            AutoGenerateColumns = false,
            SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            MultiSelect = true,
            ReadOnly = true,
            Dock = DockStyle.Fill,
            AllowUserToAddRows = false,
            AllowUserToDeleteRows = false,
            AllowUserToResizeRows = false,
            RowHeadersVisible = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill
        };

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        // Double-buffering
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);

        return dgv;
    }

    private static void ConfigureLinesGrid(DataGridView dgv)
    {
        dgv.Columns.Clear();

        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.LineNo), "Line", 4));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.SkuCode), "SKU", 8));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.SkuDescription), "Description", 24));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.OrderedQty), "Ordered", 7));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.AllocatedQty), "Allocated", 7));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.PickedQty), "Picked", 7));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.LineStatusCode), "Status", 8));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.RequestedBatch), "Req. Batch", 10));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.RequestedBbe), "Req. BBE", 8));
        dgv.Columns.Add(Col(nameof(OutboundOrderLineDto.Notes), "Notes", 17));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(OutboundOrderLineDto.LineStatusCode)) return;

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

    private static void ConfigureAllocationsGrid(DataGridView dgv)
    {
        dgv.Columns.Clear();

        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.Sscc), "SSCC", 18));
        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.SkuCode), "SKU", 8));
        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.AllocatedQty), "Qty", 5));
        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.SourceBinCode), "Bin", 7));
        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.BatchNumber), "Batch", 10));
        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.BestBeforeDate), "BBE", 8));
        dgv.Columns.Add(Col(nameof(OutboundAllocationDto.AllocationStatus), "Status", 8));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(OutboundAllocationDto.AllocationStatus)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "PENDING" => Color.DarkBlue,
                "CONFIRMED" => Color.DarkOrange,
                "PICKED" => Color.DarkGreen,
                _ => Color.DimGray
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
}
