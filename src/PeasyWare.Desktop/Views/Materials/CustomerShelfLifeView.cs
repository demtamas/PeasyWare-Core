using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Infrastructure.Ui;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Materials;

public sealed class CustomerShelfLifeView : BaseView, IToolbarAware
{
    private readonly ICustomerShelfLifeQueryRepository _queryRepo;
    private readonly ICustomerShelfLifeCommandRepository _commandRepo;
    private readonly IPartyQueryRepository _partyRepo;
    private readonly ISkuQueryRepository _skuRepo;

    private readonly bool _canManage;

    private readonly DataGridView dgv = new();
    private ToolStripButton? _btnAdd;
    private ToolStripButton? _btnEdit;
    private ToolStripButton? _btnDelete;

    private List<CustomerShelfLifeRequirementDto> _rows = new();

    public CustomerShelfLifeView(
        SessionContext session,
        ICustomerShelfLifeQueryRepository queryRepo,
        ICustomerShelfLifeCommandRepository commandRepo,
        IPartyQueryRepository partyRepo,
        ISkuQueryRepository skuRepo)
    {
        _queryRepo   = queryRepo;
        _commandRepo = commandRepo;
        _partyRepo   = partyRepo;
        _skuRepo     = skuRepo;

        // RBAC (Phase 2d) - reuses materials.manage, same category as
        // editing a SKU itself. Computed once, session lifetime is static.
        _canManage = session.HasPermission("materials.manage");

        ConfigureGrid(dgv);
        dgv.Dock = DockStyle.Fill;
        Controls.Add(dgv);

        dgv.SelectionChanged += (_, _) => UpdateToolbarState();

        Load += (_, _) => Execute(LoadRows);
    }

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
        dgv.BackgroundColor       = System.Drawing.SystemColors.Window;
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = System.Drawing.SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = System.Drawing.SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Customer",    DataPropertyName = nameof(CustomerShelfLifeRequirementDto.CustomerName),    FillWeight = 24 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SKU",         DataPropertyName = nameof(CustomerShelfLifeRequirementDto.SkuCode),          FillWeight = 12 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = nameof(CustomerShelfLifeRequirementDto.SkuDescription),   FillWeight = 24 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            HeaderText = "Min shelf life (days)",
            DataPropertyName = nameof(CustomerShelfLifeRequirementDto.MinimumRemainingShelfLifeDays),
            FillWeight = 14,
            DefaultCellStyle = new DataGridViewCellStyle { Alignment = DataGridViewContentAlignment.MiddleRight }
        });
        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            HeaderText = "Updated",
            DataPropertyName = nameof(CustomerShelfLifeRequirementDto.UpdatedAt),
            FillWeight = 14,
            DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy HH:mm" }
        });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "By", DataPropertyName = nameof(CustomerShelfLifeRequirementDto.UpdatedByUsername), FillWeight = 12 });
    }

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        var btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        btnRefresh.Click += Wrap(LoadRows);

        _btnAdd = new ToolStripButton("Add") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnAdd.Click += Wrap(AddNew);

        _btnEdit = new ToolStripButton("Edit") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnEdit.Click += Wrap(EditSelected);

        _btnDelete = new ToolStripButton("Delete") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnDelete.Click += Wrap(DeleteSelected);

        toolStrip.Items.Add(btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnAdd);
        toolStrip.Items.Add(_btnEdit);
        toolStrip.Items.Add(_btnDelete);

        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        var hasSelection = dgv.SelectedRows.Count > 0;
        _btnAdd?.GateBy(_canManage);
        if (_btnEdit   is not null) _btnEdit.GateBy(_canManage && hasSelection);
        if (_btnDelete is not null) _btnDelete.GateBy(_canManage && hasSelection);
    }

    private void LoadRows()
    {
        _rows = _queryRepo.GetAll().ToList();
        dgv.DataSource = null;
        dgv.DataSource = _rows;
        UpdateToolbarState();
    }

    private CustomerShelfLifeRequirementDto? Selected() =>
        dgv.SelectedRows.Count == 0 ? null : (CustomerShelfLifeRequirementDto)dgv.SelectedRows[0].DataBoundItem!;

    private void AddNew()
    {
        var customers = _partyRepo.GetParties("CUSTOMER");
        var skus      = _skuRepo.GetAll();

        using var form = new CustomerShelfLifeEditForm(customers, skus);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.SetRequirement(form.CustomerPartyCode, form.SkuCode, form.MinimumRemainingShelfLifeDays);
        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Shelf life requirement", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        LoadRows();
    }

    private void EditSelected()
    {
        if (Selected() is not CustomerShelfLifeRequirementDto dto) return;

        var customers = _partyRepo.GetParties("CUSTOMER");
        var skus      = _skuRepo.GetAll();

        using var form = new CustomerShelfLifeEditForm(customers, skus, dto);
        if (form.ShowDialog(this) != DialogResult.OK) return;

        var result = _commandRepo.SetRequirement(form.CustomerPartyCode, form.SkuCode, form.MinimumRemainingShelfLifeDays);
        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Shelf life requirement", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        LoadRows();
    }

    private void DeleteSelected()
    {
        if (Selected() is not CustomerShelfLifeRequirementDto dto) return;

        var confirm = MessageBox.Show(
            $"Remove the shelf-life requirement for {dto.CustomerName} / {dto.SkuCode}?\n\n" +
            "This SKU will fall back to its own default (or no requirement) for this customer.",
            "Remove requirement", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (confirm != DialogResult.Yes) return;

        var result = _commandRepo.DeleteRequirement(dto.CustomerPartyCode, dto.SkuCode);
        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Shelf life requirement", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        LoadRows();
    }
}
