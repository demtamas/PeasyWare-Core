using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Warehouse;

public partial class TasksView : BaseView, IToolbarAware
{
    private readonly AppRuntime     _runtime;
    private readonly SessionContext _session;

    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnCancel;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _chkAllHost;
    private ToolStripControlHost? _filterHost;
    private TextBox?              _txtSearch;
    private CheckBox?             _chkAll;
    private ComboBox?             _cmbFilter;
    private ToolStripLabel?       _lblStatus;

    private List<WarehouseTaskDto> _tasks = [];

    public TasksView(AppRuntime runtime, SessionContext session)
    {
        InitializeComponent();

        _runtime = runtime;
        _session = session;

        ConfigureGrid(dgvTasks);
        EnableDoubleBuffering(dgvTasks);

        dgvTasks.SelectionChanged += (_, _) => UpdateToolbarState();
        dgvTasks.CellFormatting   += OnCellFormatting;

        Load += (_, _) => LoadTasks();
    }

    // ─────────────────────────────────────────────────────────
    // IToolbarAware
    // ─────────────────────────────────────────────────────────

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadTasks);

        _btnCancel = new ToolStripButton("Cancel task")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnCancel.Click += Wrap(CancelSelected);

        _txtSearch = new TextBox { PlaceholderText = "Search SSCC / SKU / bin...", Width = 240 };
        _txtSearch.TextChanged += (_, _) => FilterGrid();

        _searchHost = new ToolStripControlHost(_txtSearch)
        {
            AutoSize = false,
            Width    = 260
        };

        _chkAll = new CheckBox
        {
            Text      = "Show all",
            Checked   = false,
            TextAlign = ContentAlignment.MiddleLeft,
            Width     = 80
        };
        _chkAll.CheckedChanged += (_, _) => LoadTasks();

        _chkAllHost = new ToolStripControlHost(_chkAll)
        {
            AutoSize = false,
            Width    = 90
        };

        _cmbFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 90 };
        _cmbFilter.Items.AddRange(["All types", "PUTAWAY", "PICK", "MOVE"]);
        _cmbFilter.SelectedIndex = 0;
        _cmbFilter.SelectedIndexChanged += (_, _) => FilterGrid();

        _filterHost = new ToolStripControlHost(_cmbFilter) { AutoSize = false, Width = 105 };

        _lblStatus = new ToolStripLabel("");

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnCancel);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_filterHost);
        toolStrip.Items.Add(_chkAllHost);
        toolStrip.Items.Add(_lblStatus);
    }

    private void UpdateToolbarState()
    {
        if (_btnCancel is null) return;
        var task = SelectedTask();
        _btnCancel.Enabled = task is not null && !task.IsTerminal;
    }

    // ─────────────────────────────────────────────────────────
    // Grid setup
    // ─────────────────────────────────────────────────────────

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
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.TaskId),         "#",           3));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.TaskTypeCode),   "Type",        5));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.TaskState),      "State",       6));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.Sscc),           "SSCC",       12));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.SkuCode),        "SKU",         5));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.SkuDescription), "Description",14));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.Quantity),       "Qty",         3));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.BatchNumber),    "Batch",       7));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.SourceBin),      "From",        5));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.DestinationBin), "To",          5));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.ClaimedBy),      "Claimed by",  6));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.CreatedBy),      "Created by",  6));
        dgv.Columns.Add(Col(nameof(WarehouseTaskDto.CompletedBy),    "Completed by",6));
        dgv.Columns.Add(ColFmt(nameof(WarehouseTaskDto.CreatedAt),   "Created",     9, "dd-MM-yyyy HH:mm"));
        dgv.Columns.Add(ColFmt(nameof(WarehouseTaskDto.UpdatedAt),   "Updated",     9, "dd-MM-yyyy HH:mm"));
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill };

    private static DataGridViewTextBoxColumn ColFmt(string prop, string header, int fill, string fmt) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill,
                DefaultCellStyle = new DataGridViewCellStyle { Format = fmt } };

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);

    private void OnCellFormatting(object? sender, DataGridViewCellFormattingEventArgs e)
    {
        if (e.RowIndex < 0) return;
        if (dgvTasks.Columns[e.ColumnIndex].DataPropertyName != nameof(WarehouseTaskDto.TaskState)) return;
        if (dgvTasks.Rows[e.RowIndex].DataBoundItem is not WarehouseTaskDto dto) return;

        e.CellStyle.ForeColor = dto.TaskStateCode switch
        {
            "OPN" => Color.DodgerBlue,
            "CLM" => Color.DarkOrange,
            "CNF" => Color.SeaGreen,
            "CNL" => Color.Gray,
            "EXP" => Color.Firebrick,
            _     => dgvTasks.DefaultCellStyle.ForeColor
        };
    }

    // ─────────────────────────────────────────────────────────
    // Data
    // ─────────────────────────────────────────────────────────

    private void LoadTasks()
    {
        var repo  = _runtime.Repositories.CreateWarehouseTaskQuery(_session);
        _tasks    = repo.GetTasks(activeOnly: !(_chkAll?.Checked ?? false)).ToList();
        FilterGrid();
        if (_lblStatus is not null)
            _lblStatus.Text = $"{_tasks.Count} task(s)";
    }

    private void FilterGrid()
    {
        var term     = _txtSearch?.Text.Trim() ?? "";
        var typeFilter = _cmbFilter?.SelectedIndex > 0 ? _cmbFilter.SelectedItem?.ToString() : null;

        var data = _tasks
            .Where(t => typeFilter is null || t.TaskTypeCode == typeFilter)
            .Where(t => string.IsNullOrEmpty(term) ||
                t.Sscc.Contains(term, StringComparison.OrdinalIgnoreCase)                       ||
                t.SkuCode.Contains(term, StringComparison.OrdinalIgnoreCase)                    ||
                (t.SourceBin?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false)      ||
                (t.DestinationBin?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false) ||
                (t.CreatedBy?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false)      ||
                (t.ClaimedBy?.Contains(term, StringComparison.OrdinalIgnoreCase) ?? false)
            ).ToList();

        dgvTasks.DataSource = null;
        dgvTasks.DataSource = data;
    }

    private WarehouseTaskDto? SelectedTask() =>
        dgvTasks.SelectedRows.Count == 0 ? null
        : dgvTasks.SelectedRows[0].DataBoundItem as WarehouseTaskDto;

    // ─────────────────────────────────────────────────────────
    // Actions
    // ─────────────────────────────────────────────────────────

    private void CancelSelected()
    {
        var task = SelectedTask();
        if (task is null) return;

        var confirm = MessageBox.Show(
            this,
            $"Cancel task #{task.TaskId} ({task.TaskTypeCode} — {task.Sscc})?\n\nThis cannot be undone.",
            "Cancel Task",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var repo   = _runtime.Repositories.CreateWarehouseTaskCommand(_session);
        var result = repo.CancelTask(task.TaskId, "Cancelled by supervisor via Desktop");

        if (result.Success)
            Execute(LoadTasks);
        else
            MessageBox.Show(this, result.FriendlyMessage, "Cancel Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }
}
