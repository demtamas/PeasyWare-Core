using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Parties;

public partial class PartiesView : BaseView, IToolbarAware
{
    private readonly IPartyQueryRepository   _queryRepo;
    private readonly IPartyCommandRepository _commandRepo;

    private readonly string? _roleFilter;   // null = All

    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnNew;
    private ToolStripButton?      _btnEdit;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _filterHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbFilter;

    private List<PartyDto> _parties = [];

    public PartiesView(
        IPartyQueryRepository   queryRepo,
        IPartyCommandRepository commandRepo,
        string?                 roleFilter = null)
    {
        InitializeComponent();

        _queryRepo   = queryRepo;
        _commandRepo = commandRepo;
        _roleFilter  = roleFilter;

        ConfigureGrid(dgvParties);
        EnableDoubleBuffering(dgvParties);

        dgvParties.SelectionChanged += (_, _) => UpdateToolbarState();
        dgvParties.CellDoubleClick  += (_, e) => { if (e.RowIndex >= 0) Execute(EditSelected); };

        Load += (_, _) => Execute(LoadParties);
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadParties);

        _btnNew = new ToolStripButton("New party") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(AddNew);

        _btnEdit = new ToolStripButton("Edit")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnEdit.Click += Wrap(EditSelected);

        _txtSearch = new TextBox { PlaceholderText = "Search code / name / tax ID...", Width = 240 };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();
        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 260 };

        _cmbFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 110 };
        _cmbFilter.Items.AddRange(["All roles", "Supplier", "Customer", "Haulier", "Owner"]);
        _cmbFilter.SelectedIndex = _roleFilter switch
        {
            "SUPPLIER" => 1,
            "CUSTOMER" => 2,
            "HAULIER"  => 3,
            "OWNER"    => 4,
            _          => 0
        };
        _cmbFilter.SelectedIndexChanged += (_, _) => Execute(LoadParties);
        _filterHost = new ToolStripControlHost(_cmbFilter) { AutoSize = false, Width = 125 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNew);
        toolStrip.Items.Add(_btnEdit);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_filterHost);
    }

    private void UpdateToolbarState()
    {
        if (_btnEdit is not null)
            _btnEdit.Enabled = dgvParties.SelectedRows.Count == 1;
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
        dgv.Columns.Add(Col(nameof(PartyDto.PartyCode),    "Code",         10));
        dgv.Columns.Add(Col(nameof(PartyDto.DisplayName),  "Display Name", 20));
        dgv.Columns.Add(Col(nameof(PartyDto.LegalName),    "Legal Name",   20));
        dgv.Columns.Add(Col(nameof(PartyDto.Roles),        "Roles",        14));
        dgv.Columns.Add(Col(nameof(PartyDto.CountryCode),  "Country",       5));
        dgv.Columns.Add(Col(nameof(PartyDto.TaxId),        "Tax ID",        9));
        dgv.Columns.Add(Col(nameof(PartyDto.IsActive),     "Active",        5));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(PartyDto.IsActive)) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not PartyDto party) return;
            e.Value               = party.IsActive ? "Yes" : "No";
            e.CellStyle.ForeColor = party.IsActive ? Color.DarkGreen : Color.Gray;
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

    private void LoadParties()
    {
        var role = _cmbFilter?.SelectedIndex switch
        {
            1 => "SUPPLIER",
            2 => "CUSTOMER",
            3 => "HAULIER",
            4 => "OWNER",
            _ => (string?)null
        };

        _parties = _queryRepo.GetParties(roleFilter: role, includeInactive: true).ToList();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _parties
            : _parties.Where(p =>
                p.PartyCode.Contains(q, StringComparison.OrdinalIgnoreCase)   ||
                p.DisplayName.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                p.LegalName.Contains(q, StringComparison.OrdinalIgnoreCase)   ||
                (p.TaxId ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        dgvParties.DataSource = null;
        dgvParties.DataSource = data;
    }

    private PartyDto? Selected() =>
        dgvParties.SelectedRows.Count == 0 ? null
        : dgvParties.SelectedRows[0].DataBoundItem as PartyDto;

    // ==========================================================
    // Actions
    // ==========================================================

    private void AddNew()
    {
        using var form = new PartyEditForm(null);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.CreateParty(
            partyCode:   form.PartyCode,
            legalName:   form.LegalName,
            displayName: form.DisplayName,
            countryCode: form.CountryCode,
            taxId:        form.TaxId,
            roles:        form.Roles);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Create Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        Execute(LoadParties);
    }

    private void EditSelected()
    {
        if (Selected() is not PartyDto party) return;

        using var form = new PartyEditForm(party);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.UpdateParty(
            partyId:     party.PartyId,
            legalName:   form.LegalName,
            displayName: form.DisplayName,
            countryCode: form.CountryCode,
            taxId:        form.TaxId,
            isActive:    form.IsActive,
            roles:        form.Roles);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Update Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        Execute(LoadParties);
    }
}
