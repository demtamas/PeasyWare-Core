using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class StorageTypesView : BaseView, IToolbarAware
{
    private readonly IStorageTypeRepository _repo;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnNew;
    private ToolStripButton? _btnEdit;
    private ToolStripButton? _btnDeactivate;
    private ToolStripButton? _btnReactivate;
    private ToolStripButton? _btnShowInactive;
    private ToolStripButton? _btnDelete;

    private bool _showInactive = false;

    private readonly DataGridView _dgv = new();

    public StorageTypesView(IStorageTypeRepository repo)
    {
        _repo = repo;
        ConfigureGrid(_dgv);
        EnableDoubleBuffering(_dgv);
        _dgv.Dock              = DockStyle.Fill;
        _dgv.SelectionChanged += (_, _) => UpdateToolbarState();
        _dgv.CellDoubleClick  += (_, e) => { if (e.RowIndex >= 0) Execute(EditSelected); };
        Controls.Add(_dgv);
        AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Load += (_, _) => Execute(LoadStorageTypes);
    }

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadStorageTypes);

        _btnNew = new ToolStripButton("New storage type") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewStorageType);

        _btnEdit = new ToolStripButton("Edit") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnEdit.Click += Wrap(EditSelected);

        _btnDeactivate = new ToolStripButton("Deactivate") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnDeactivate.Click += Wrap(DeactivateSelected);

        _btnReactivate = new ToolStripButton("Reactivate") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnReactivate.Click += Wrap(ReactivateSelected);

        _btnShowInactive = new ToolStripButton("Show inactive") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnShowInactive.Click += Wrap(ToggleInactive);

        _btnDelete = new ToolStripButton("Delete") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false, ForeColor = Color.DarkRed };
        _btnDelete.Click += Wrap(DeleteSelected);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNew);
        toolStrip.Items.Add(_btnEdit);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnDeactivate);
        toolStrip.Items.Add(_btnReactivate);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnShowInactive);
        toolStrip.Items.Add(_btnDelete);
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
        dgv.BackgroundColor       = SystemColors.Window;
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Code",        DataPropertyName = nameof(StorageTypeDto.StorageTypeCode),   FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Name",        DataPropertyName = nameof(StorageTypeDto.StorageTypeName),   FillWeight = 14 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = nameof(StorageTypeDto.Description),       FillWeight = 24 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Total bins",  DataPropertyName = nameof(StorageTypeDto.TotalBins),         FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active bins", DataPropertyName = nameof(StorageTypeDto.ActiveBins),        FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active",      DataPropertyName = nameof(StorageTypeDto.IsActive),          FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created",     DataPropertyName = nameof(StorageTypeDto.CreatedAt),         FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created by",  DataPropertyName = nameof(StorageTypeDto.CreatedByUsername), FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Updated",     DataPropertyName = nameof(StorageTypeDto.UpdatedAt),         FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy HH:mm" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Updated by",  DataPropertyName = nameof(StorageTypeDto.UpdatedByUsername), FillWeight = 6  });

        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not StorageTypeDto t) return;
            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = t.IsActive
                ? SystemColors.Window
                : Color.FromArgb(235, 235, 235);
            dgv.Rows[e.RowIndex].DefaultCellStyle.ForeColor = t.IsActive
                ? SystemColors.WindowText
                : Color.Gray;
        };
    }

    private void LoadStorageTypes()
    {
        _dgv.DataSource = null;
        _dgv.DataSource = _repo.GetStorageTypes(includeInactive: _showInactive).ToList();
        if (_btnShowInactive is not null)
            _btnShowInactive.Text = _showInactive ? "Hide inactive" : "Show inactive";
        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        var t = Selected();
        if (_btnEdit       is not null) _btnEdit.Enabled       = t is not null;
        if (_btnDeactivate is not null) _btnDeactivate.Enabled = t is not null &&  t.IsActive;
        if (_btnReactivate is not null) _btnReactivate.Enabled = t is not null && !t.IsActive;
        if (_btnDelete     is not null) _btnDelete.Enabled     = t is not null;
    }

    private void DeleteSelected()
    {
        if (Selected() is not StorageTypeDto t) return;
        if (t.TotalBins > 0)
        { MessageBox.Show(this, $"{t.TotalBins} bin(s) use this storage type. Reassign or delete them first.", "Cannot Delete", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        var confirm = MessageBox.Show(this, $"Permanently delete storage type {t.StorageTypeCode}?", "Confirm Delete",
            MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (confirm != DialogResult.Yes) return;
        var result = _repo.DeleteStorageType(t.StorageTypeCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Delete", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadStorageTypes);
    }

    private void NewStorageType()
    {
        using var form = new EditZoneSectionForm("New Storage Type", "Type code", "Type name");
        if (form.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.CreateStorageType(form.Code, form.DisplayName, form.Description);
        if (!result.Success)
        { MessageBox.Show(this, result.FriendlyMessage, "Cannot Create", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        Execute(LoadStorageTypes);
    }

    private void EditSelected()
    {
        if (Selected() is not StorageTypeDto t) return;
        using var form = new EditZoneSectionForm("Edit Storage Type", "Type code", "Type name", t.StorageTypeCode, t.StorageTypeName, t.Description);
        if (form.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.UpdateStorageType(t.StorageTypeCode, form.DisplayName, form.Description, form.ClearDescription);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Update", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadStorageTypes);
    }

    private void DeactivateSelected()
    {
        if (Selected() is not StorageTypeDto t) return;
        var confirm = MessageBox.Show(this,
            $"Deactivate storage type {t.StorageTypeCode}?\n\nExisting bins keep this type assigned.",
            "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (confirm != DialogResult.Yes) return;
        var result = _repo.DeactivateStorageType(t.StorageTypeCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Deactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadStorageTypes);
    }

    private void ReactivateSelected()
    {
        if (Selected() is not StorageTypeDto t) return;
        var result = _repo.ReactivateStorageType(t.StorageTypeCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Reactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadStorageTypes);
    }

    private void ToggleInactive()
    {
        _showInactive = !_showInactive;
        Execute(LoadStorageTypes);
    }

    private StorageTypeDto? Selected() =>
        _dgv.SelectedRows.Count == 1 && _dgv.SelectedRows[0].DataBoundItem is StorageTypeDto t ? t : null;

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
