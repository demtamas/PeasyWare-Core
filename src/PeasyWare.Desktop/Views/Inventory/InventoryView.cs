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
    private readonly Guid                    _sessionId;
    private readonly IInventoryQueryRepository _repo;

    private ToolStripButton? _btnRefresh;
    private TextBox?         _txtSearch;
    private ToolStripControlHost? _searchHost;

    private List<ActiveInventoryDto> _inventory = new();

    public InventoryView(Guid sessionId, IInventoryQueryRepository repo)
    {
        InitializeComponent();

        _sessionId = sessionId;
        _repo      = repo;

        ConfigureGrid(dgvInventory);
        EnableDoubleBuffering(dgvInventory);

        Load += (_, _) => LoadInventory();
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();
        toolStrip.ImageScalingSize = new Size(16, 16);

        _btnRefresh = new ToolStripButton("Refresh")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text
        };
        _btnRefresh.Click += Wrap(RefreshInventory);

        _txtSearch              = new TextBox();
        _txtSearch.PlaceholderText = "Search SSCC / SKU / batch / bin…";
        _txtSearch.Width        = 260;
        _txtSearch.TextChanged += (_, _) => ApplyFilter();

        _searchHost = new ToolStripControlHost(_txtSearch)
        {
            AutoSize = false,
            Width    = 280,
            Alignment = ToolStripItemAlignment.Left
        };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadInventory()
    {
        _inventory = _repo.GetAllActiveInventory().ToList();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        if (_txtSearch is null)
        {
            Bind(_inventory);
            return;
        }

        var q = _txtSearch.Text.Trim();

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

    private void RefreshInventory()
    {
        Execute(LoadInventory);
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

        dgv.RowHeadersVisible    = false;
        dgv.AutoSizeColumnsMode  = DataGridViewAutoSizeColumnsMode.Fill;

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor              = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor              = Color.Black;

        dgv.Columns.Clear();

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.Sscc),
            HeaderText       = "SSCC",
            FillWeight       = 20
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.SkuCode),
            HeaderText       = "SKU",
            FillWeight       = 10
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.SkuDescription),
            HeaderText       = "Description",
            FillWeight       = 22
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.BatchNumber),
            HeaderText       = "Batch",
            FillWeight       = 12
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.BestBeforeDate),
            HeaderText       = "BBE",
            FillWeight       = 10,
            DefaultCellStyle = new DataGridViewCellStyle { Format = "dd-MM-yyyy" }
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.Quantity),
            HeaderText       = "Qty",
            FillWeight       = 6
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.StockState),
            HeaderText       = "State",
            FillWeight       = 7
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.StockStatus),
            HeaderText       = "Status",
            FillWeight       = 7
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.BinCode),
            HeaderText       = "Bin",
            FillWeight       = 9
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.StorageTypeCode),
            HeaderText       = "Type",
            FillWeight       = 7
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.LastMovementType),
            HeaderText       = "Last Move",
            FillWeight       = 9
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(ActiveInventoryDto.LastMovementAt),
            HeaderText       = "Last Move At",
            FillWeight       = 14,
            DefaultCellStyle = new DataGridViewCellStyle { Format = "dd-MM-yyyy HH:mm" }
        });
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
