using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Logs;

public partial class SkuAuditView : BaseView, IToolbarAware
{
    private readonly IAuditQueryRepository _repo;
    private readonly ToolTip               _copyHint = new() { InitialDelay = 0, ReshowDelay = 0 };

    private ToolStripButton?      _btnRefresh;
    private TextBox?              _txtSkuFilter;
    private DateTimePicker?       _dtFrom;
    private DateTimePicker?       _dtTo;
    private ToolStripButton?      _btnClearFilter;

    private List<SkuChangeLogDto> _rows = new();

    public SkuAuditView(IAuditQueryRepository repo)
    {
        InitializeComponent();

        _repo = repo;

        ConfigureGrid(dgvSkuAudit);
        EnableDoubleBuffering(dgvSkuAudit);

        dgvSkuAudit.CellDoubleClick += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            var val = dgvSkuAudit[e.ColumnIndex, e.RowIndex].FormattedValue?.ToString();
            if (string.IsNullOrEmpty(val)) return;

            try { ClipboardHelper.SetText(val); } catch { }

            var pt = dgvSkuAudit.GetCellDisplayRectangle(e.ColumnIndex, e.RowIndex, true);
            _copyHint.Show("Copied!", dgvSkuAudit, pt.X, pt.Y - 20, 1200);
        };

        Load += (_, _) => Execute(LoadData);
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadData);

        _txtSkuFilter = new TextBox { Width = 100, PlaceholderText = "SKU code…" };
        _txtSkuFilter.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) Execute(LoadData); };
        var skuHost = new ToolStripControlHost(_txtSkuFilter) { AutoSize = false, Width = 110 };

        _dtFrom = new DateTimePicker { Format = DateTimePickerFormat.Short, Width = 90, Value = DateTime.Today.AddMonths(-1) };
        var fromHost = new ToolStripControlHost(_dtFrom) { AutoSize = false, Width = 100 };

        _dtTo = new DateTimePicker { Format = DateTimePickerFormat.Short, Width = 90, Value = DateTime.Today };
        var toHost = new ToolStripControlHost(_dtTo) { AutoSize = false, Width = 100 };

        _btnClearFilter = new ToolStripButton("Clear filter") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnClearFilter.Click += Wrap(ClearFilter);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(new ToolStripLabel("SKU:"));
        toolStrip.Items.Add(skuHost);
        toolStrip.Items.Add(new ToolStripLabel("From:"));
        toolStrip.Items.Add(fromHost);
        toolStrip.Items.Add(new ToolStripLabel("To:"));
        toolStrip.Items.Add(toHost);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnClearFilter);
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadData()
    {
        var skuCode = string.IsNullOrWhiteSpace(_txtSkuFilter?.Text) ? null : _txtSkuFilter!.Text.Trim().ToUpperInvariant();
        var from    = _dtFrom is not null ? DateOnly.FromDateTime(_dtFrom.Value) : (DateOnly?)null;
        var to      = _dtTo   is not null ? DateOnly.FromDateTime(_dtTo.Value)   : (DateOnly?)null;

        _rows = _repo.GetSkuChanges(skuCode, from, to).ToList();
        Bind();
    }

    private void ClearFilter()
    {
        if (_txtSkuFilter is not null) _txtSkuFilter.Text = "";
        if (_dtFrom is not null) _dtFrom.Value = DateTime.Today.AddMonths(-1);
        if (_dtTo   is not null) _dtTo.Value   = DateTime.Today;
        LoadData();
    }

    private void Bind()
    {
        dgvSkuAudit.DataSource = null;
        dgvSkuAudit.DataSource = _rows;
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns = false;
        dgv.SelectionMode       = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect         = false;
        dgv.ReadOnly            = true;
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

        dgv.Columns.Add(Col("OccurredAt",  "When",           9,  "dd-MM-yyyy HH:mm:ss"));
        dgv.Columns.Add(Col("Username",    "User",           6));
        dgv.Columns.Add(Col("ActionType",  "Action",         5));
        dgv.Columns.Add(Col("SkuCode",     "SKU",            5));
        dgv.Columns.Add(Col("DescBefore",  "Desc (before)",  14));
        dgv.Columns.Add(Col("DescAfter",   "Desc (after)",   14));
        dgv.Columns.Add(Col("StorageBefore","Storage (bef)", 6));
        dgv.Columns.Add(Col("StorageAfter", "Storage (aft)", 6));
        dgv.Columns.Add(Col("SectionBefore","Section (bef)", 6));
        dgv.Columns.Add(Col("SectionAfter", "Section (aft)", 6));
        dgv.Columns.Add(Col("OwnerBefore",  "Owner (bef)",   7));
        dgv.Columns.Add(Col("OwnerAfter",   "Owner (aft)",   7));
        dgv.Columns.Add(BoolCol("BatchReqBefore", "Batch req (bef)", 7));
        dgv.Columns.Add(BoolCol("BatchReqAfter",  "Batch req (aft)", 7));
        dgv.Columns.Add(BoolCol("ActiveBefore",   "Active (bef)",    5));
        dgv.Columns.Add(BoolCol("ActiveAfter",    "Active (aft)",    5));

        // Colour-code action type
        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != "ActionType") return;
            var val = e.Value?.ToString();
            e.CellStyle.ForeColor = val == "INSERT" ? Color.DarkGreen : Color.DarkBlue;
            e.CellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
        };
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill, string? format = null)
    {
        var col = new DataGridViewTextBoxColumn
        {
            DataPropertyName = prop,
            HeaderText       = header,
            FillWeight       = fill
        };
        if (format is not null)
            col.DefaultCellStyle = new DataGridViewCellStyle { Format = format };
        return col;
    }

    private static DataGridViewCheckBoxColumn BoolCol(string prop, string header, int fill)
        => new()
        {
            DataPropertyName = prop,
            HeaderText       = header,
            FillWeight       = fill,
            FalseValue       = false,
            TrueValue        = true,
            IndeterminateValue = null
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
