using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Inbound;

public partial class InboundView : BaseView, IToolbarAware
{
    private readonly IInboundQueryRepository   _queryRepo;
    private readonly IInboundCommandRepository _commandRepo;
    private readonly ISkuQueryRepository       _skuRepo;
    private readonly IPartyQueryRepository     _partyRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnNew;
    private ToolStripButton?      _btnDetails;
    private ToolStripButton?      _btnCancel;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _filterHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbFilter;

    private List<InboundDeliverySummaryDto> _deliveries = [];

    public InboundView(
        IInboundQueryRepository   queryRepo,
        IInboundCommandRepository commandRepo,
        ISkuQueryRepository       skuRepo,
        IPartyQueryRepository     partyRepo)
    {
        InitializeComponent();

        _queryRepo   = queryRepo;
        _commandRepo = commandRepo;
        _skuRepo     = skuRepo;
        _partyRepo   = partyRepo;

        ConfigureGrid(dgvInbound);
        EnableDoubleBuffering(dgvInbound);

        dgvInbound.SelectionChanged += (_, _) => UpdateToolbarState();
        dgvInbound.CellDoubleClick  += (_, e) => { if (e.RowIndex >= 0) Execute(OpenDetails); };

        Load += (_, _) => Execute(LoadDeliveries);
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadDeliveries);

        _btnNew = new ToolStripButton("New inbound") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewInbound);

        _btnCancel = new ToolStripButton("Cancel inbound")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnCancel.Click += Wrap(CancelSelected);

        _btnDetails = new ToolStripButton("Inbound details")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnDetails.Click += Wrap(OpenDetails);

        _txtSearch = new TextBox { PlaceholderText = "Search ref / supplier / haulier...", Width = 240 };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();
        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 260 };

        _cmbFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 100 };
        _cmbFilter.Items.AddRange(["Active", "Closed", "All"]);
        _cmbFilter.SelectedIndex = 0;
        _cmbFilter.SelectedIndexChanged += (_, _) => Execute(LoadDeliveries);
        _filterHost = new ToolStripControlHost(_cmbFilter) { AutoSize = false, Width = 115 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNew);
        toolStrip.Items.Add(_btnCancel);
        toolStrip.Items.Add(_btnDetails);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_filterHost);
    }

    private void UpdateToolbarState()
    {
        var selected = Selected();
        if (_btnDetails is not null)
            _btnDetails.Enabled = selected is not null;
        if (_btnCancel is not null)
            _btnCancel.Enabled = selected is not null
                && selected.StatusCode is "EXP" or "ACT";
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns   = false;
        dgv.SelectionMode         = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect           = false;
        dgv.ReadOnly              = true;
        dgv.AllowUserToAddRows    = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;
        dgv.RowHeadersVisible     = false;
        dgv.AutoSizeColumnsMode   = DataGridViewAutoSizeColumnsMode.Fill;

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Clear();
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.InboundRef),      "Inbound Ref",   12));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.StatusCode),      "Status",         7));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.InboundMode),     "Mode",            5));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.SupplierName),    "Supplier",       14));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.HaulierName),     "Haulier",        12));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.ExpectedArrival), "Expected",        9));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.TotalLines),      "Lines",           4));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.TotalExpected),   "Expected",        6));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.TotalReceived),   "Received",        6));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.TotalOutstanding),"Outstanding",     7));
        dgv.Columns.Add(Col(nameof(InboundDeliverySummaryDto.TotalUnits),      "Units",           5));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName
                != nameof(InboundDeliverySummaryDto.StatusCode)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "NEW"  => Color.DimGray,
                "ACT"  => Color.DarkOrange,
                "RCV"  => Color.DarkBlue,
                "CLS"  => Color.DarkGreen,
                "CNL"  => Color.Gray,
                _      => Color.Black
            };
        };
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill };

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadDeliveries()
    {
        string? statusFilter = _cmbFilter?.SelectedIndex switch
        {
            0 => null,   // Active — no filter, handled below
            1 => "CLS",  // Closed
            _ => null    // All — no filter
        };

        // For "Active" we exclude CLS and CNL
        var all = _queryRepo.GetInboundDeliveries(statusFilter).ToList();

        _deliveries = _cmbFilter?.SelectedIndex == 0
            ? all.Where(d => d.StatusCode != "CLS" && d.StatusCode != "CNL").ToList()
            : all;

        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _deliveries
            : _deliveries.Where(d =>
                d.InboundRef.Contains(q, StringComparison.OrdinalIgnoreCase)              ||
                (d.SupplierName?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false) ||
                (d.HaulierName?.Contains(q, StringComparison.OrdinalIgnoreCase)  ?? false) ||
                (d.InboundMode?.Contains(q, StringComparison.OrdinalIgnoreCase)  ?? false) ||
                d.StatusCode.Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        dgvInbound.DataSource = null;
        dgvInbound.DataSource = data;
    }

    private InboundDeliverySummaryDto? Selected() =>
        dgvInbound.SelectedRows.Count == 0 ? null
        : dgvInbound.SelectedRows[0].DataBoundItem as InboundDeliverySummaryDto;

    private void CancelSelected()
    {
        var delivery = Selected();
        if (delivery is null) return;

        var confirm = MessageBox.Show(
            this,
            $"Cancel inbound delivery {delivery.InboundRef}?\n\nThis cannot be undone.",
            "Confirm Cancellation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.CancelInbound(delivery.InboundRef);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Cancel",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        Execute(LoadDeliveries);
    }

    private void NewInbound()
    {
        using var form = new CreateInboundForm(_commandRepo, _skuRepo, _partyRepo);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        MessageBox.Show(this,
            $"Inbound {form.CreatedInboundRef} created successfully.",
            "Inbound Created",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);

        Execute(LoadDeliveries);
    }

    private void OpenDetails()
    {
        var delivery = Selected();
        if (delivery is null) return;

        using var form = new InboundDetailForm(delivery, _queryRepo);
        form.ShowDialog(this);

        // Refresh in case activation or receipt changed status
        Execute(LoadDeliveries);
    }
}
