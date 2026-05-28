using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Logs;

public sealed class LocationAuditView : BaseView, IToolbarAware
{
    private readonly IAuditQueryRepository _repo;
    private readonly ToolTip               _copyHint = new() { InitialDelay = 0, ReshowDelay = 0 };

    private ToolStripButton?      _btnRefresh;
    private TextBox?              _txtBinFilter;
    private DateTimePicker?       _dtFrom;
    private DateTimePicker?       _dtTo;
    private ToolStripButton?      _btnClearFilter;

    private List<LocationChangeLogDto> _rows = [];

    private readonly DataGridView _dgv = new();

    public LocationAuditView(IAuditQueryRepository repo)
    {
        _repo = repo;

        ConfigureGrid(_dgv);
        EnableDoubleBuffering(_dgv);
        _dgv.Dock = DockStyle.Fill;

        _dgv.CellDoubleClick += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            var val = _dgv[e.ColumnIndex, e.RowIndex].FormattedValue?.ToString();
            if (string.IsNullOrEmpty(val)) return;
            try { Clipboard.SetText(val); } catch { }
            var pt = _dgv.GetCellDisplayRectangle(e.ColumnIndex, e.RowIndex, true);
            _copyHint.Show("Copied!", _dgv, pt.X, pt.Y - 20, 1200);
        };

        Controls.Add(_dgv);
        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Size                = new Size(1400, 686);

        Load += (_, _) => Execute(LoadData);
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadData);

        _txtBinFilter = new TextBox { Width = 100, PlaceholderText = "Bin code…" };
        _txtBinFilter.KeyDown += (_, e) => { if (e.KeyCode == Keys.Enter) Execute(LoadData); };
        var binHost = new ToolStripControlHost(_txtBinFilter) { AutoSize = false, Width = 110 };

        _dtFrom = new DateTimePicker { Format = DateTimePickerFormat.Short, Width = 90, Value = DateTime.Today.AddMonths(-1) };
        var fromHost = new ToolStripControlHost(_dtFrom) { AutoSize = false, Width = 100 };

        _dtTo = new DateTimePicker { Format = DateTimePickerFormat.Short, Width = 90, Value = DateTime.Today };
        var toHost = new ToolStripControlHost(_dtTo) { AutoSize = false, Width = 100 };

        _btnClearFilter = new ToolStripButton("Clear filter") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnClearFilter.Click += Wrap(ClearFilter);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(new ToolStripLabel("Bin:"));
        toolStrip.Items.Add(binHost);
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
        var binCode = string.IsNullOrWhiteSpace(_txtBinFilter?.Text) ? null : _txtBinFilter!.Text.Trim().ToUpperInvariant();
        var from    = _dtFrom is not null ? DateOnly.FromDateTime(_dtFrom.Value) : (DateOnly?)null;
        var to      = _dtTo   is not null ? DateOnly.FromDateTime(_dtTo.Value)   : (DateOnly?)null;

        _rows = _repo.GetLocationChanges(binCode, from, to).ToList();
        _dgv.DataSource = null;
        _dgv.DataSource = _rows;
    }

    private void ClearFilter()
    {
        if (_txtBinFilter is not null) _txtBinFilter.Text = "";
        if (_dtFrom is not null) _dtFrom.Value = DateTime.Today.AddMonths(-1);
        if (_dtTo   is not null) _dtTo.Value   = DateTime.Today;
        Execute(LoadData);
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
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.OccurredAt),   "When",           9, "dd/MM/yyyy HH:mm:ss"));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.Username),     "User",           5));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.ActionType),   "Action",         6));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.BinCode),      "Bin",            7));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.BinCodeBefore),"Code (before)",  7));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.BinCodeAfter), "Code (after)",   7));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.TypeBefore),   "Type (before)",  6));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.TypeAfter),    "Type (after)",   6));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.SectionBefore),"Section (bef)",  6));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.SectionAfter), "Section (aft)",  6));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.ZoneBefore),   "Zone (before)",  5));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.ZoneAfter),    "Zone (after)",   5));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.CapacityBefore),"Cap (before)",  5));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.CapacityAfter), "Cap (after)",   5));
        dgv.Columns.Add(BoolCol(nameof(LocationChangeLogDto.ActiveBefore), "Active (bef)", 5));
        dgv.Columns.Add(BoolCol(nameof(LocationChangeLogDto.LockedBefore), "Locked (bef)", 5));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.Reason),       "Reason",         10));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.NotesBefore),  "Notes (before)", 10));
        dgv.Columns.Add(Col(nameof(LocationChangeLogDto.NotesAfter),   "Notes (after)",  10));

        // Suppress sort glyph
        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        // Action type colour
        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(LocationChangeLogDto.ActionType)) return;
            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "CREATE"     => Color.DarkGreen,
                "UPDATE"     => Color.DarkBlue,
                "LOCK"       => Color.DarkOrange,
                "DEACTIVATE" => Color.DarkRed,
                "REACTIVATE" => Color.SeaGreen,
                _            => Color.Gray
            };
            e.CellStyle.Font = new Font(dgv.Font, FontStyle.Bold);
        };

        // Highlight rows where a value actually changed
        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not LocationChangeLogDto row) return;
            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = row.ActionType switch
            {
                "DEACTIVATE" => Color.FromArgb(255, 240, 240),
                "LOCK"       => Color.FromArgb(255, 248, 225),
                "CREATE"     => Color.FromArgb(240, 255, 240),
                _            => SystemColors.Window
            };
        };
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill, string? format = null)
    {
        var col = new DataGridViewTextBoxColumn { DataPropertyName = prop, HeaderText = header, FillWeight = fill };
        if (format is not null) col.DefaultCellStyle = new DataGridViewCellStyle { Format = format };
        return col;
    }

    private static DataGridViewCheckBoxColumn BoolCol(string prop, string header, int fill) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill,
                FalseValue = false, TrueValue = true, IndeterminateValue = null };

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
