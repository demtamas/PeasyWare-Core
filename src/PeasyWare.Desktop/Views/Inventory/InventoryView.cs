using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Inventory;

public partial class InventoryView : BaseView, IToolbarAware
{
    private readonly Guid                       _sessionId;
    private readonly IInventoryQueryRepository  _queryRepo;
    private readonly IInventoryCommandRepository _commandRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnSelectAll;
    private ToolStripButton?      _btnChangeStatus;
    private ToolStripControlHost? _searchHost;
    private TextBox?              _txtSearch;

    private List<ActiveInventoryDto> _inventory = new();

    public InventoryView(
        Guid                        sessionId,
        IInventoryQueryRepository   queryRepo,
        IInventoryCommandRepository commandRepo)
    {
        InitializeComponent();

        _sessionId   = sessionId;
        _queryRepo   = queryRepo;
        _commandRepo = commandRepo;

        ConfigureGrid(dgvInventory);
        EnableDoubleBuffering(dgvInventory);

        dgvInventory.SelectionChanged += (_, _) => UpdateToolbarState();
        dgvInventory.CellDoubleClick  += DgvInventory_CellDoubleClick;

        Load += (_, _) => LoadInventory();
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(RefreshInventory);

        _btnSelectAll = new ToolStripButton("Select all") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnSelectAll.Click += (_, _) => dgvInventory.SelectAll();

        _btnChangeStatus = new ToolStripButton("Change status")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnChangeStatus.Click += Wrap(ChangeStatus);

        _txtSearch = new TextBox
        {
            PlaceholderText = "Search SSCC / SKU / batch / bin…",
            Width           = 260
        };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();

        _searchHost = new ToolStripControlHost(_txtSearch)
        {
            AutoSize  = false,
            Width     = 280,
            Alignment = ToolStripItemAlignment.Left
        };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnSelectAll);
        toolStrip.Items.Add(_btnChangeStatus);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
    }

    private void UpdateToolbarState()
    {
        var count = dgvInventory.SelectedRows.Count;
        if (_btnChangeStatus is not null)
        {
            _btnChangeStatus.Enabled = count > 0;
            _btnChangeStatus.Text    = count > 1
                ? $"Change status ({count})"
                : "Change status";
        }
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadInventory()
    {
        _inventory = _queryRepo.GetAllActiveInventory().ToList();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";

        var data = string.IsNullOrWhiteSpace(q)
            ? _inventory
            : _inventory.Where(i =>
                (i.Sscc           ?? "").Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (i.SkuCode        ?? "").Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (i.BatchNumber    ?? "").Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (i.BinCode        ?? "").Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (i.SkuDescription ?? "").Contains(q, StringComparison.OrdinalIgnoreCase))
              .ToList();

        Bind(data.ToList());
    }

    private void Bind(List<ActiveInventoryDto> data)
    {
        dgvInventory.DataSource = null;
        dgvInventory.DataSource = data;
    }

    private void RefreshInventory() => Execute(LoadInventory);

    // ==========================================================
    // Double-click: copy cell value to clipboard
    // ==========================================================

    private void DgvInventory_CellDoubleClick(object? sender, DataGridViewCellEventArgs e)
    {
        if (e.RowIndex < 0 || e.ColumnIndex < 0) return;

        var cell = dgvInventory[e.ColumnIndex, e.RowIndex];
        var val  = cell.FormattedValue?.ToString();

        if (string.IsNullOrEmpty(val)) return;

        ClipboardHelper.SetText(val);
        ShowCopiedHint(cell);
    }

    // Persistent tooltip instance — prevents GC from collecting it before it shows
    private readonly ToolTip _copyHint = new() { IsBalloon = false, InitialDelay = 0, ReshowDelay = 0 };

    private void ShowCopiedHint(DataGridViewCell cell)
    {
        var pt = dgvInventory.GetCellDisplayRectangle(cell.ColumnIndex, cell.RowIndex, true);
        _copyHint.Show("Copied!", dgvInventory, pt.X, pt.Y - 20, 1200);
    }

    // ==========================================================
    // Status change
    // ==========================================================

    private void ChangeStatus()
    {
        var selected = dgvInventory.SelectedRows
            .Cast<DataGridViewRow>()
            .Select(r => r.DataBoundItem as ActiveInventoryDto)
            .Where(d => d is not null)
            .Cast<ActiveInventoryDto>()
            .ToList();

        if (selected.Count == 0) return;

        using var form = new StatusChangeForm(selected.Count);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        // Confirmation for large batches
        if (selected.Count > 1)
        {
            var confirm = MessageBox.Show(
                this,
                $"You are about to change the status of {selected.Count} unit(s) to {form.NewStatusCode}.\n\nThis cannot be undone automatically. Continue?",
                "Confirm Status Change",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (confirm != DialogResult.Yes) return;
        }

        var result = _commandRepo.UpdateStockStatus(
            ssccs:         selected.Select(d => d.Sscc),
            newStatusCode: form.NewStatusCode,
            reason:        form.Reason);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Status Change Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        MessageBox.Show(this,
            $"{selected.Count} unit(s) updated to {form.NewStatusCode}.",
            "PeasyWare Inventory", MessageBoxButtons.OK, MessageBoxIcon.Information);

        Execute(LoadInventory);
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns = false;
        dgv.SelectionMode       = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect         = true;   // Ctrl+click and Shift+click supported
        dgv.ReadOnly            = true;

        dgv.AllowUserToAddRows    = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;

        dgv.RowHeadersVisible   = false;
        dgv.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor              = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor              = Color.Black;

        dgv.Columns.Clear();

        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.Sscc),            "SSCC",         20));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.SkuCode),         "SKU",          10));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.SkuDescription),  "Description",  20));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.BatchNumber),     "Batch",        11));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.BestBeforeDate),  "BBE",           9, "dd-MM-yyyy"));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.Quantity),        "Qty",           5));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.StockState),      "State",         6));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.StockStatus),     "Status",        6));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.BinCode),         "Bin",           8));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.StorageTypeCode), "Type",          6));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.Reference),       "Reference",    12));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.AllocationStatus),  "Alloc",         6));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.LastMovementType),  "Last Move",     8));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.LastMovementAt),    "Last Move At", 12, "dd-MM-yyyy HH:mm"));
        dgv.Columns.Add(Col(nameof(ActiveInventoryDto.ReceivedAt),        "Received At",  12, "dd-MM-yyyy HH:mm"));

        // Colour-code Reference column: order refs in blue, inbound refs in grey
        // Colour-code Alloc column: CONFIRMED/PICKED in orange, PENDING in yellow
        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            var propName = dgv.Columns[e.ColumnIndex].DataPropertyName;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not ActiveInventoryDto dto) return;

            if (propName == nameof(ActiveInventoryDto.Reference))
            {
                e.CellStyle.ForeColor = dto.OrderRef is not null
                    ? System.Drawing.Color.DarkBlue
                    : System.Drawing.Color.DimGray;
            }
            else if (propName == nameof(ActiveInventoryDto.AllocationStatus))
            {
                e.CellStyle.ForeColor = dto.AllocationStatus switch
                {
                    "CONFIRMED" or "PICKED" => System.Drawing.Color.DarkOrange,
                    "PENDING"               => System.Drawing.Color.Goldenrod,
                    _                       => dgv.DefaultCellStyle.ForeColor
                };
            }
        };
    }

    private static DataGridViewTextBoxColumn Col(
        string prop, string header, int fill, string? format = null)
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

    private static void EnableDoubleBuffering(DataGridView dgv)
    {
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
    }
}
