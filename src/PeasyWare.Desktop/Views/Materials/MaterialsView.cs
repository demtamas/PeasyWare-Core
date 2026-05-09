using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Microsoft.Data.SqlClient;
using PeasyWare.Infrastructure.Sql;

namespace PeasyWare.Desktop.Views.Materials;

public partial class MaterialsView : BaseView, IToolbarAware
{
    private readonly ISkuQueryRepository   _queryRepo;
    private readonly ISkuCommandRepository _commandRepo;
    private readonly SqlConnectionFactory  _connectionFactory;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnAdd;
    private ToolStripButton? _btnEdit;
    private ToolStripButton? _btnCopy;
    private ToolStripButton? _btnToggleActive;
    private TextBox?         _txtSearch;

    private List<SkuDto>         _skus    = new();
    private bool                 _showAll = false;
    private List<StorageLookup>  _storageTypes = new();
    private List<StorageLookup>  _sections     = new();

    public MaterialsView(
        ISkuQueryRepository   queryRepo,
        ISkuCommandRepository commandRepo,
        SqlConnectionFactory  connectionFactory)
    {
        InitializeComponent();

        _queryRepo         = queryRepo;
        _commandRepo       = commandRepo;
        _connectionFactory = connectionFactory;

        ConfigureGrid(dgvMaterials);
        EnableDoubleBuffering(dgvMaterials);

        dgvMaterials.SelectionChanged += (_, _) => UpdateToolbarState();
        dgvMaterials.CellDoubleClick  += (_, _) => Execute(EditSelected);

        Load += (_, _) => Execute(InitialLoad);
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadSkus);

        _btnAdd = new ToolStripButton("New SKU") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnAdd.Click += Wrap(AddNew);

        _btnEdit = new ToolStripButton("Edit") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnEdit.Click += Wrap(EditSelected);

        _btnCopy = new ToolStripButton("Copy") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnCopy.Click += Wrap(CopySelected);

        _btnToggleActive = new ToolStripButton("Show inactive") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnToggleActive.Click += Wrap(ToggleShowAll);

        _txtSearch = new TextBox { Width = 240, PlaceholderText = "Search SKU / description / EAN…" };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();

        var searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 250 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnAdd);
        toolStrip.Items.Add(_btnEdit);
        toolStrip.Items.Add(_btnCopy);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnToggleActive);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(searchHost);
    }

    private void UpdateToolbarState()
    {
        var hasSelection = dgvMaterials.SelectedRows.Count > 0;
        if (_btnEdit  is not null) _btnEdit.Enabled  = hasSelection;
        if (_btnCopy  is not null) _btnCopy.Enabled  = hasSelection;
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadSkus()
    {
        _skus = _queryRepo.GetAll(includeInactive: _showAll).ToList();
        ApplyFilter();

        if (_btnToggleActive is not null)
            _btnToggleActive.Text = _showAll ? "Hide inactive" : "Show inactive";
    }

    private void InitialLoad()
    {
        LoadLookups();
        LoadSkus();
    }

    private void LoadLookups()
    {
        _storageTypes.Clear();
        _sections.Clear();

        using var conn = _connectionFactory.Create();
        conn.Open();

        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT storage_type_code, storage_type_name FROM locations.storage_types WHERE is_active = 1 ORDER BY storage_type_code";
            using var r = cmd.ExecuteReader();
            while (r.Read())
                _storageTypes.Add(new StorageLookup(r.GetString(0), $"{r.GetString(0)} — {r.GetString(1)}"));
        }

        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT section_code, section_name FROM locations.storage_sections ORDER BY section_code";
            using var r = cmd.ExecuteReader();
            while (r.Read())
                _sections.Add(new StorageLookup(r.GetString(0), $"{r.GetString(0)} — {r.GetString(1)}"));
        }
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";

        var data = string.IsNullOrWhiteSpace(q)
            ? _skus
            : _skus.Where(s =>
                s.SkuCode.Contains(q, StringComparison.OrdinalIgnoreCase)        ||
                s.SkuDescription.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                (s.Ean ?? "").Contains(q, StringComparison.OrdinalIgnoreCase))
              .ToList();

        dgvMaterials.DataSource = null;
        dgvMaterials.DataSource = data;

        UpdateToolbarState();
    }

    private void ToggleShowAll()
    {
        _showAll = !_showAll;
        LoadSkus();
    }

    // ==========================================================
    // Actions
    // ==========================================================

    private void AddNew()
    {
        using var form = new SkuEditForm(null, _storageTypes, _sections);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.CreateSku(
            skuCode:            form.SkuCode,
            skuDescription:     form.SkuDescription,
            ean:                form.Ean,
            uomCode:            form.UomCode,
            weightPerUnit:      form.WeightPerUnit,
            standardHuQuantity: form.StandardHuQuantity,
            isHazardous:        form.IsHazardous);

        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Create SKU",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        LoadSkus();
        SelectBySkuCode(form.SkuCode);
    }

    private void EditSelected()
    {
        if (GetSelectedSku() is not SkuDto dto) return;

        using var form = new SkuEditForm(dto, _storageTypes, _sections);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.UpdateSku(
            skuCode:            form.SkuCode,
            skuDescription:     form.SkuDescription,
            ean:                form.Ean,
            uomCode:            form.UomCode,
            weightPerUnit:      form.WeightPerUnit,
            standardHuQuantity: form.StandardHuQuantity,
            isHazardous:        form.IsHazardous,
            isActive:           form.IsActive);

        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Update SKU",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        LoadSkus();
        SelectBySkuCode(form.SkuCode);
    }

    private void CopySelected()
    {
        if (GetSelectedSku() is not SkuDto source) return;

        // Pre-populate with source but clear SKU code for operator to fill
        var template = source with
        {
            SkuCode        = "",
            SkuDescription = source.SkuDescription + " (copy)",
            Ean            = null
        };

        using var form = new SkuEditForm(template, _storageTypes, _sections);
        // Unlock SKU code for the copy
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.CreateSku(
            skuCode:            form.SkuCode,
            skuDescription:     form.SkuDescription,
            ean:                form.Ean,
            uomCode:            form.UomCode,
            weightPerUnit:      form.WeightPerUnit,
            standardHuQuantity: form.StandardHuQuantity,
            isHazardous:        form.IsHazardous);

        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Copy SKU",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        LoadSkus();
        SelectBySkuCode(form.SkuCode);
    }

    // ==========================================================
    // Helpers
    // ==========================================================

    private SkuDto? GetSelectedSku()
    {
        if (dgvMaterials.SelectedRows.Count == 0) return null;
        return dgvMaterials.SelectedRows[0].DataBoundItem as SkuDto;
    }

    private void SelectBySkuCode(string skuCode)
    {
        foreach (DataGridViewRow row in dgvMaterials.Rows)
        {
            if (row.DataBoundItem is SkuDto s && s.SkuCode == skuCode)
            {
                dgvMaterials.ClearSelection();
                row.Selected = true;
                dgvMaterials.FirstDisplayedScrollingRowIndex = row.Index;
                break;
            }
        }
    }

    // ==========================================================
    // Grid setup
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

        dgv.Columns.Add(Col(nameof(SkuDto.SkuCode),                   "SKU Code",       10));
        dgv.Columns.Add(Col(nameof(SkuDto.SkuDescription),              "Description",    25));
        dgv.Columns.Add(Col(nameof(SkuDto.Ean),                         "EAN",            10));
        dgv.Columns.Add(Col(nameof(SkuDto.UomCode),                     "UOM",             5));
        dgv.Columns.Add(Col(nameof(SkuDto.PreferredStorageTypeCode),    "Storage",         7));
        dgv.Columns.Add(Col(nameof(SkuDto.PreferredSectionCode),         "Section",         7));
        dgv.Columns.Add(Col(nameof(SkuDto.WeightPerUnit),               "Weight (kg)",     7,
            new DataGridViewCellStyle { Format = "F3", Alignment = DataGridViewContentAlignment.MiddleRight }));
        dgv.Columns.Add(Col(nameof(SkuDto.StandardHuQuantity),          "HU Qty",          5,
            new DataGridViewCellStyle { Alignment = DataGridViewContentAlignment.MiddleRight }));
        dgv.Columns.Add(BoolCol(nameof(SkuDto.IsBatchRequired),         "Batch Req",       6));
        dgv.Columns.Add(BoolCol(nameof(SkuDto.IsHazardous),             "Hazardous",       6));
        dgv.Columns.Add(BoolCol(nameof(SkuDto.IsActive),                "Active",          5));
        dgv.Columns.Add(Col(nameof(SkuDto.UpdatedByUsername),           "Updated By",      7));
        dgv.Columns.Add(Col(nameof(SkuDto.UpdatedAt),                   "Updated At",      7,
            new DataGridViewCellStyle { Format = "dd-MM-yyyy HH:mm" }));
    }

    private static DataGridViewTextBoxColumn Col(
        string name, string header, int fill,
        DataGridViewCellStyle? style = null)
    {
        var col = new DataGridViewTextBoxColumn
        {
            DataPropertyName = name,
            HeaderText       = header,
            FillWeight       = fill
        };
        if (style is not null) col.DefaultCellStyle = style;
        return col;
    }

    private static DataGridViewCheckBoxColumn BoolCol(string name, string header, int fill)
        => new()
        {
            DataPropertyName = name,
            HeaderText       = header,
            FillWeight       = fill,
            FalseValue       = false,
            TrueValue        = true
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
