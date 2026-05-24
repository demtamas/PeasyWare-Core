using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Movements;

public partial class MovementsView : BaseView, IToolbarAware
{
    private readonly IMovementQueryRepository _queryRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _typeFilterHost;
    private ToolStripControlHost? _fromDateHost;
    private ToolStripControlHost? _toDateHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbType;
    private DateTimePicker?       _dtpFrom;
    private DateTimePicker?       _dtpTo;

    private List<MovementDto> _movements = [];

    public MovementsView(IMovementQueryRepository queryRepo)
    {
        InitializeComponent();

        _queryRepo = queryRepo;

        ConfigureGrid(dgvMovements);
        EnableDoubleBuffering(dgvMovements);

        Load += (_, _) => Execute(LoadMovements);
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadMovements);

        _txtSearch = new TextBox { PlaceholderText = "Search SSCC / SKU / bin...", Width = 200 };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();
        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 220 };

        _cmbType = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
        _cmbType.Items.AddRange(["All types", "INBOUND", "PUTAWAY", "MOVE", "PICK", "SHIP", "ADJUSTMENT"]);
        _cmbType.SelectedIndex = 0;
        _cmbType.SelectedIndexChanged += (_, _) => Execute(LoadMovements);
        _typeFilterHost = new ToolStripControlHost(_cmbType) { AutoSize = false, Width = 125 };

        _dtpFrom = new DateTimePicker { Format = DateTimePickerFormat.Short, Value = DateTime.Today.AddDays(-7), Width = 90 };
        _dtpFrom.ValueChanged += (_, _) => Execute(LoadMovements);
        _fromDateHost = new ToolStripControlHost(_dtpFrom) { AutoSize = false, Width = 95 };

        _dtpTo = new DateTimePicker { Format = DateTimePickerFormat.Short, Value = DateTime.Today, Width = 90 };
        _dtpTo.ValueChanged += (_, _) => Execute(LoadMovements);
        _toDateHost = new ToolStripControlHost(_dtpTo) { AutoSize = false, Width = 95 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_typeFilterHost);
        toolStrip.Items.Add(new ToolStripLabel("From:"));
        toolStrip.Items.Add(_fromDateHost);
        toolStrip.Items.Add(new ToolStripLabel("To:"));
        toolStrip.Items.Add(_toDateHost);
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
        dgv.BackgroundColor       = SystemColors.Window;

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Clear();
        dgv.Columns.Add(Col(nameof(MovementDto.MovedAt),       "Moved At",     10));
        dgv.Columns.Add(Col(nameof(MovementDto.MovementType),  "Type",          7));
        dgv.Columns.Add(Col(nameof(MovementDto.Sscc),          "SSCC",         14));
        dgv.Columns.Add(Col(nameof(MovementDto.SkuCode),       "SKU",           7));
        dgv.Columns.Add(Col(nameof(MovementDto.SkuDescription),"Description",  14));
        dgv.Columns.Add(Col(nameof(MovementDto.MovedQty),      "Qty",           3));
        dgv.Columns.Add(Col(nameof(MovementDto.FromBin),       "From",          6));
        dgv.Columns.Add(Col(nameof(MovementDto.ToBin),         "To",            6));
        dgv.Columns.Add(Col(nameof(MovementDto.FromState),     "Fr.State",      5));
        dgv.Columns.Add(Col(nameof(MovementDto.ToState),       "To.State",      5));
        dgv.Columns.Add(Col(nameof(MovementDto.ReferenceRef),  "Reference",     8));
        dgv.Columns.Add(Col(nameof(MovementDto.MovedBy),       "By",            5));

        // Colour code movement type
        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(MovementDto.MovementType)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "INBOUND"    => Color.Teal,
                "PUTAWAY"    => Color.DarkGreen,
                "MOVE"       => Color.DarkOrange,
                "PICK"       => Color.DarkBlue,
                "SHIP"       => Color.Purple,
                "ADJUSTMENT" => Color.DarkRed,
                _            => Color.Black
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

    private void LoadMovements()
    {
        var typeFilter = _cmbType?.SelectedIndex is > 0
            ? _cmbType.SelectedItem?.ToString()
            : null;

        _movements = _queryRepo.GetMovements(
            movementTypeFilter: typeFilter,
            fromDate:           _dtpFrom?.Value.Date,
            toDate:             _dtpTo?.Value.Date
        ).ToList();

        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _movements
            : _movements.Where(m =>
                m.Sscc.Contains(q, StringComparison.OrdinalIgnoreCase)              ||
                m.SkuCode.Contains(q, StringComparison.OrdinalIgnoreCase)           ||
                m.SkuDescription.Contains(q, StringComparison.OrdinalIgnoreCase)    ||
                (m.FromBin    ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)||
                (m.ToBin      ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)||
                (m.ReferenceRef ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)||
                m.MovedBy.Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        dgvMovements.DataSource = null;
        dgvMovements.DataSource = data;
    }
}
