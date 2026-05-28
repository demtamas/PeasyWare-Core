using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class LocationsView : BaseView, IToolbarAware
{
    private readonly ILocationQueryRepository   _queryRepo;
    private readonly ILocationCommandRepository _commandRepo;
    private readonly IInventoryQueryRepository  _inventoryRepo;

    // Toolbar
    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnNewBin;
    private ToolStripButton?      _btnBulkCreate;
    private ToolStripButton?      _btnEdit;
    private ToolStripButton?      _btnLock;
    private ToolStripButton?      _btnUnlock;
    private ToolStripButton?      _btnDeactivate;
    private ToolStripButton?      _btnReactivate;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _typeFilterHost;
    private ToolStripControlHost? _stockFilterHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbTypeFilter;
    private ComboBox?             _cmbStockFilter;

    // Detail panel — location property card
    private readonly DataGridView _dgvLocations = new();

    private List<LocationDto> _locations = [];

    public LocationsView(
        ILocationQueryRepository   queryRepo,
        ILocationCommandRepository commandRepo,
        IInventoryQueryRepository  inventoryRepo)
    {
        _queryRepo     = queryRepo;
        _commandRepo   = commandRepo;
        _inventoryRepo = inventoryRepo;

        BuildLayout();
        ConfigureMainGrid(_dgvLocations);
        EnableDoubleBuffering(_dgvLocations);

        _dgvLocations.SelectionChanged += (_, _) => UpdateToolbarState();

        Load += (_, _) => Execute(LoadLocations);
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadLocations);

        _btnNewBin = new ToolStripButton("New location") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNewBin.Click += Wrap(NewBin);

        _btnBulkCreate = new ToolStripButton("Bulk create") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnBulkCreate.Click += Wrap(BulkCreate);

        _btnEdit = new ToolStripButton("Edit") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnEdit.Click += Wrap(EditSelected);

        _btnLock = new ToolStripButton("Lock") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnLock.Click += Wrap(LockSelected);

        _btnUnlock = new ToolStripButton("Unlock") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnUnlock.Click += Wrap(UnlockSelected);

        _btnDeactivate = new ToolStripButton("Deactivate") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnDeactivate.Click += Wrap(DeactivateSelected);

        _btnReactivate = new ToolStripButton("Reactivate") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnReactivate.Click += Wrap(ReactivateSelected);

        _txtSearch = new TextBox { PlaceholderText = "Search bin / SKU / SSCC...", Width = 200 };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();
        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 218 };

        _cmbTypeFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 80 };
        _cmbTypeFilter.Items.Add("All types");
        foreach (var t in _queryRepo.GetStorageTypeCodes())
            _cmbTypeFilter.Items.Add(t);
        _cmbTypeFilter.SelectedIndex = 0;
        _cmbTypeFilter.SelectedIndexChanged += (_, _) => Execute(LoadLocations);
        _typeFilterHost = new ToolStripControlHost(_cmbTypeFilter) { AutoSize = false, Width = 95 };

        _cmbStockFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 100 };
        _cmbStockFilter.Items.AddRange(["With stock", "All locations"]);
        _cmbStockFilter.SelectedIndex = 0;
        _cmbStockFilter.SelectedIndexChanged += (_, _) => Execute(LoadLocations);
        _stockFilterHost = new ToolStripControlHost(_cmbStockFilter) { AutoSize = false, Width = 115 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNewBin);
        toolStrip.Items.Add(_btnBulkCreate);
        toolStrip.Items.Add(_btnEdit);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnLock);
        toolStrip.Items.Add(_btnUnlock);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnDeactivate);
        toolStrip.Items.Add(_btnReactivate);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_typeFilterHost);
        toolStrip.Items.Add(_stockFilterHost);
    }

    // ==========================================================
    // Layout — main grid left, detail panel right
    // ==========================================================

    private void BuildLayout()
    {
        _dgvLocations.Dock = DockStyle.Fill;
        Controls.Add(_dgvLocations);
        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Size                = new Size(1300, 686);
    }

    // ==========================================================
    // Grid config
    // ==========================================================

    private static void ConfigureMainGrid(DataGridView dgv)
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
        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor     = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor     = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Bin",         DataPropertyName = nameof(LocationDto.BinCode),        FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Type",        DataPropertyName = nameof(LocationDto.StorageTypeCode), FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Section",     DataPropertyName = nameof(LocationDto.SectionCode),     FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Zone",        DataPropertyName = nameof(LocationDto.ZoneCode),        FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Cap",         DataPropertyName = nameof(LocationDto.Capacity),        FillWeight = 3  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Units",       DataPropertyName = nameof(LocationDto.UnitCount),       FillWeight = 3  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Locked",      DataPropertyName = nameof(LocationDto.IsLocked),        FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SKU",         DataPropertyName = nameof(LocationDto.SkuCode),         FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = nameof(LocationDto.SkuDescription),  FillWeight = 14 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Batch",       DataPropertyName = nameof(LocationDto.BatchNumber),     FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "BBE",         DataPropertyName = nameof(LocationDto.BestBeforeDate),  FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "State",       DataPropertyName = nameof(LocationDto.StockState),      FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Status",      DataPropertyName = nameof(LocationDto.StockStatus),     FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Notes",       DataPropertyName = nameof(LocationDto.Notes),           FillWeight = 10 });

        // Suppress sort highlight on column headers
        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        // Row colouring
        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not LocationDto loc) return;

            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = (!loc.IsActive, loc.IsLocked, loc.UnitCount > 0) switch
            {
                (true,  _, _)    => Color.FromArgb(235, 235, 235),  // inactive = grey
                (false, true, _) => Color.FromArgb(255, 240, 230),  // locked   = amber
                (false, false, true)  => SystemColors.Window,
                _                => Color.FromArgb(248, 248, 248)   // empty    = slight grey
            };

            // Lock indicator on Bin column
            if (loc.IsLocked)
            {
                dgv.Rows[e.RowIndex].Cells[0].Style.ForeColor = Color.DarkOrange;
                dgv.Rows[e.RowIndex].Cells[0].Style.Font      = new Font(dgv.Font, FontStyle.Bold);
            }
        };
    }

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadLocations()
    {
        var withStock = _cmbStockFilter?.SelectedIndex == 0;
        var typeCode  = _cmbTypeFilter?.SelectedIndex > 0 ? _cmbTypeFilter.SelectedItem?.ToString() : null;

        _locations = _queryRepo.GetLocations(
            withStockOnly:   withStock,
            storageTypeCode: typeCode
        ).ToList();

        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _locations
            : _locations.Where(l =>
                l.BinCode.Contains(q, StringComparison.OrdinalIgnoreCase)              ||
                (l.SkuCode       ?? "").Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (l.SkuDescription ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)||
                (l.Sscc          ?? "").Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (l.BatchNumber   ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        _dgvLocations.DataSource = null;
        _dgvLocations.DataSource = data;
        UpdateToolbarState();
    }

    // ==========================================================
    // Actions
    // ==========================================================

    private void EditSelected()
    {
        if (Selected() is not LocationDto loc) return;

        using var form = new EditBinForm(
            loc.BinCode,
            loc.UnitCount > 0,
            loc.StorageTypeCode,
            loc.ZoneCode,
            loc.SectionCode,
            loc.Capacity,
            loc.Notes,
            _commandRepo,
            _queryRepo);

        if (form.ShowDialog(this) != DialogResult.OK) return;
        Execute(LoadLocations);
    }

    private void LockSelected()
    {
        if (Selected() is not LocationDto loc) return;

        using var input = new LockReasonForm(loc.BinCode);
        if (input.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.LockBin(loc.BinCode, input.Reason);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Lock", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        Execute(LoadLocations);
    }

    private void UnlockSelected()
    {
        if (Selected() is not LocationDto loc) return;

        var confirm = MessageBox.Show(this,
            $"Unlock location {loc.BinCode}?",
            "Confirm Unlock",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.UnlockBin(loc.BinCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Unlock", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        Execute(LoadLocations);
    }

    private void NewBin()
    {
        using var form = new CreateBinForm(_commandRepo, _queryRepo);
        if (form.ShowDialog(this) != DialogResult.OK) return;
        Execute(LoadLocations);
    }

    private void BulkCreate()
    {
        using var form = new CreateBinsBulkForm(_commandRepo, _queryRepo);
        if (form.ShowDialog(this) != DialogResult.OK) return;
        Execute(LoadLocations);
    }

    private void DeactivateSelected()
    {
        if (Selected() is not LocationDto loc) return;

        using var input = new LockReasonForm($"Deactivate {loc.BinCode}");
        if (input.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.DeactivateBin(loc.BinCode, input.Reason);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Deactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        Execute(LoadLocations);
    }

    private void ReactivateSelected()
    {
        if (Selected() is not LocationDto loc) return;

        var confirm = MessageBox.Show(this,
            $"Reactivate location {loc.BinCode}?",
            "Confirm Reactivation",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.ReactivateBin(loc.BinCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Reactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        Execute(LoadLocations);
    }

    private void UpdateToolbarState()
    {
        var loc = Selected();
        if (_btnEdit       is not null) _btnEdit.Enabled       = loc is not null;
        if (_btnLock       is not null) _btnLock.Enabled       = loc is not null &&  loc.IsActive && !loc.IsLocked;
        if (_btnUnlock     is not null) _btnUnlock.Enabled     = loc is not null &&  loc.IsActive &&  loc.IsLocked;
        if (_btnDeactivate is not null) _btnDeactivate.Enabled = loc is not null &&  loc.IsActive;
        if (_btnReactivate is not null) _btnReactivate.Enabled = loc is not null && !loc.IsActive;
    }

    private LocationDto? Selected() =>
        _dgvLocations.SelectedRows.Count == 1 &&
        _dgvLocations.SelectedRows[0].DataBoundItem is LocationDto loc
            ? loc : null;
}
