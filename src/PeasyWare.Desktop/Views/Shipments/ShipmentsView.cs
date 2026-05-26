using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Shipments;

public partial class ShipmentsView : BaseView, IToolbarAware
{
    private readonly IOutboundQueryRepository    _queryRepo;
    private readonly IOutboundCommandRepository  _commandRepo;
    private readonly IShipmentManifestRepository _manifestRepo;
    private readonly ISettingsQueryRepository    _settingsRepo;
    private readonly IPartyQueryRepository       _partyRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnNew;
    private ToolStripButton?      _btnCancelShipment;
    private ToolStripButton?      _btnDetails;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _filterHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbFilter;

    private List<ShipmentSummaryDto> _shipments = [];

    public ShipmentsView(
        IOutboundQueryRepository    queryRepo,
        IOutboundCommandRepository  commandRepo,
        IShipmentManifestRepository manifestRepo,
        ISettingsQueryRepository    settingsRepo,
        IPartyQueryRepository       partyRepo)
    {
        InitializeComponent();

        _queryRepo    = queryRepo;
        _commandRepo  = commandRepo;
        _manifestRepo = manifestRepo;
        _settingsRepo = settingsRepo;
        _partyRepo    = partyRepo;

        ConfigureGrid(dgvShipments);
        EnableDoubleBuffering(dgvShipments);

        dgvShipments.SelectionChanged  += (_, _) => UpdateToolbarState();
        dgvShipments.CellDoubleClick   += (_, e) => { if (e.RowIndex >= 0) Execute(OpenDetails); };

        Load += (_, _) => LoadShipments();
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadShipments);

        _btnNew = new ToolStripButton("New shipment") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewShipment);

        _btnCancelShipment = new ToolStripButton("Cancel shipment")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnCancelShipment.Click += Wrap(CancelSelected);

        _btnDetails = new ToolStripButton("Shipment details")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnDetails.Click += Wrap(OpenDetails);

        _txtSearch = new TextBox { PlaceholderText = "Search ref / vehicle / haulier...", Width = 240 };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();

        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 260 };

        _cmbFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 100 };
        _cmbFilter.Items.AddRange(["Active", "Shipped", "All"]);
        _cmbFilter.SelectedIndex = 0;
        _cmbFilter.SelectedIndexChanged += (_, _) => Execute(LoadShipments);

        _filterHost = new ToolStripControlHost(_cmbFilter) { AutoSize = false, Width = 115 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNew);
        toolStrip.Items.Add(_btnCancelShipment);
        toolStrip.Items.Add(_btnDetails);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_filterHost);
    }

    // ==========================================================
    // Grid setup
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
        dgv.DefaultCellStyle.SelectionBackColor              = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor              = Color.Black;

        dgv.Columns.Clear();
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.ShipmentRef),      "Shipment Ref",      10));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.ShipmentStatus),   "Status",             7));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.VehicleRef),       "Vehicle",            8));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.HaulierName),      "Haulier",           14));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.PlannedDeparture), "Planned Departure", 12));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.TotalOrders),      "Orders",             5));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.OrdersPicked),     "Picked",             5));
        dgv.Columns.Add(Col(nameof(ShipmentSummaryDto.OrdersLoaded),     "Loaded",             5));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(ShipmentSummaryDto.ShipmentStatus)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "OPEN"     => Color.DimGray,
                "LOADING"  => Color.DarkOrange,
                "LOADED"   => Color.DarkBlue,
                "SHIPPED"  => Color.DarkGreen,
                "DEPARTED" => Color.SeaGreen,
                _          => Color.Black
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

    private void LoadShipments()
    {
        _shipments = (_cmbFilter?.SelectedIndex switch
        {
            1 => _queryRepo.GetShippedShipments(),
            2 => _queryRepo.GetAllShipments(),
            _ => _queryRepo.GetActiveShipments()
        }).ToList();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _shipments
            : _shipments.Where(s =>
                s.ShipmentRef.Contains(q, StringComparison.OrdinalIgnoreCase)               ||
                (s.VehicleRef?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false)    ||
                (s.HaulierName?.Contains(q, StringComparison.OrdinalIgnoreCase) ?? false)   ||
                s.ShipmentStatus.Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        dgvShipments.DataSource = null;
        dgvShipments.DataSource = data;
    }

    private ShipmentSummaryDto? SelectedShipment() =>
        dgvShipments.SelectedRows.Count == 0 ? null
        : dgvShipments.SelectedRows[0].DataBoundItem as ShipmentSummaryDto;

    private void OpenDetails()
    {
        var shipment = SelectedShipment();
        if (shipment is null) return;

        using var form = new ShipmentDetailForm(
            shipment.ShipmentId,
            shipment.ShipmentRef,
            _queryRepo,
            _commandRepo,
            _manifestRepo,
            _settingsRepo);
        form.ShowDialog(this);
    }

    private void UpdateToolbarState()
    {
        var s = SelectedShipment();
        if (_btnDetails        is not null) _btnDetails.Enabled        = s is not null;
        if (_btnCancelShipment is not null) _btnCancelShipment.Enabled = s is not null
            && s.ShipmentStatus is "OPEN" or "LOADING";
    }

    private void NewShipment()
    {
        using var form = new CreateShipmentForm(_commandRepo, _queryRepo, _partyRepo);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        MessageBox.Show(this,
            $"Shipment {form.CreatedShipmentRef} created successfully.",
            "Created",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);

        Execute(LoadShipments);
    }

    private void CancelSelected()
    {
        var shipment = SelectedShipment();
        if (shipment is null) return;

        var confirm = MessageBox.Show(
            this,
            $"Cancel shipment {shipment.ShipmentRef}?\n\nOrders on this shipment will be removed from it.",
            "Confirm Cancellation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.CancelShipment(shipment.ShipmentRef);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Cancel",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        Execute(LoadShipments);
    }
}
