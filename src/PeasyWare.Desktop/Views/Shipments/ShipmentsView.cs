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
    private readonly IOutboundQueryRepository _queryRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _filterHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbFilter;

    private List<ShipmentSummaryDto> _shipments = [];

    public ShipmentsView(IOutboundQueryRepository queryRepo)
    {
        InitializeComponent();

        _queryRepo = queryRepo;

        ConfigureGrid(dgvShipments);
        EnableDoubleBuffering(dgvShipments);

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
}
