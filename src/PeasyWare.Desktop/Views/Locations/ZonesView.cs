using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Infrastructure.Ui;
using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class ZonesView : BaseView, IToolbarAware
{
    private readonly IZoneRepository               _repo;
    private readonly ILocationQueryRepository      _locationQuery;
    private readonly ILocationCommandRepository    _locationCommand;

    // RBAC (Phase 2d) - computed once, session lifetime is static
    private readonly bool _canManageZones;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnNew;
    private ToolStripButton? _btnEdit;
    private ToolStripButton? _btnAssign;
    private ToolStripButton? _btnDeactivate;
    private ToolStripButton? _btnReactivate;
    private ToolStripButton? _btnShowInactive;
    private ToolStripButton? _btnDelete;

    private bool _showInactive = false;

    private readonly DataGridView _dgv = new();

    public ZonesView(
        IZoneRepository            repo,
        ILocationQueryRepository   locationQuery,
        ILocationCommandRepository locationCommand,
        SessionContext             session)
    {
        _repo            = repo;
        _locationQuery   = locationQuery;
        _locationCommand = locationCommand;
        _canManageZones  = session.HasPermission("zones.manage");
        ConfigureGrid(_dgv);
        EnableDoubleBuffering(_dgv);
        _dgv.Dock              = DockStyle.Fill;
        _dgv.SelectionChanged += (_, _) => UpdateToolbarState();
        _dgv.CellDoubleClick  += (_, e) => { if (e.RowIndex >= 0) Execute(EditSelected); };
        Controls.Add(_dgv);
        AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Load += (_, _) => Execute(LoadZones);
    }

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadZones);

        _btnNew = new ToolStripButton("New zone") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewZone);
        _btnNew.GateBy(_canManageZones);

        _btnEdit = new ToolStripButton("Edit") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnEdit.Click += Wrap(EditSelected);

        _btnAssign = new ToolStripButton("Assign to locations") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnAssign.Click += Wrap(AssignToLocations);

        _btnDeactivate = new ToolStripButton("Deactivate") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnDeactivate.Click += Wrap(DeactivateSelected);

        _btnReactivate = new ToolStripButton("Reactivate") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnReactivate.Click += Wrap(ReactivateSelected);

        _btnShowInactive = new ToolStripButton("Show inactive") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnShowInactive.Click += Wrap(ToggleInactive);

        _btnDelete = new ToolStripButton("Delete") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false, ForeColor = System.Drawing.Color.DarkRed };
        _btnDelete.Click += Wrap(DeleteSelected);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnNew);
        toolStrip.Items.Add(_btnEdit);
        toolStrip.Items.Add(_btnAssign);
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
        dgv.BackgroundColor       = System.Drawing.SystemColors.Window;
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = System.Drawing.SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = System.Drawing.SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Code",        DataPropertyName = nameof(ZoneDto.ZoneCode),          FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Name",        DataPropertyName = nameof(ZoneDto.ZoneName),          FillWeight = 14 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = nameof(ZoneDto.Description),       FillWeight = 24 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Total bins",  DataPropertyName = nameof(ZoneDto.TotalBins),         FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active bins", DataPropertyName = nameof(ZoneDto.ActiveBins),        FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active",      DataPropertyName = nameof(ZoneDto.IsActive),          FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created",     DataPropertyName = nameof(ZoneDto.CreatedAt),         FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created by",  DataPropertyName = nameof(ZoneDto.CreatedByUsername), FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Updated",     DataPropertyName = nameof(ZoneDto.UpdatedAt),         FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy HH:mm" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Updated by",  DataPropertyName = nameof(ZoneDto.UpdatedByUsername), FillWeight = 6  });

        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not ZoneDto z) return;
            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = z.IsActive
                ? System.Drawing.SystemColors.Window
                : Color.FromArgb(235, 235, 235);
            dgv.Rows[e.RowIndex].DefaultCellStyle.ForeColor = z.IsActive
                ? System.Drawing.SystemColors.WindowText
                : Color.Gray;
        };
    }

    private void LoadZones()
    {
        _dgv.DataSource = null;
        _dgv.DataSource = _repo.GetZones(includeInactive: _showInactive).ToList();
        if (_btnShowInactive is not null)
            _btnShowInactive.Text = _showInactive ? "Hide inactive" : "Show inactive";
        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        var z = Selected();
        if (_btnEdit       is not null) _btnEdit.Enabled       = _canManageZones && z is not null;
        if (_btnAssign     is not null) _btnAssign.Enabled     = _canManageZones && z is not null;
        if (_btnDeactivate is not null) _btnDeactivate.Enabled = _canManageZones && z is not null &&  z.IsActive;
        if (_btnReactivate is not null) _btnReactivate.Enabled = _canManageZones && z is not null && !z.IsActive;
        if (_btnDelete     is not null) _btnDelete.Enabled     = _canManageZones && z is not null;
    }

    private void AssignToLocations()
    {
        if (Selected() is not ZoneDto zone) return;

        using var form = new AssignLocationsForm(
            $"Assign locations to zone: {zone.ZoneCode} — {zone.ZoneName}",
            "Assign",
            _locationQuery,
            binCodes =>
            {
                var result = _locationCommand.AssignBinsToZone(zone.ZoneCode, binCodes);
                return result.Success ? null : result.FriendlyMessage;
            });

        form.ShowDialog(this);
        Execute(LoadZones);
    }

    private void DeleteSelected()
    {
        if (Selected() is not ZoneDto z) return;
        if (z.TotalBins > 0)
        { MessageBox.Show(this, $"{z.TotalBins} bin(s) are assigned to this zone. Reassign them first.", "Cannot Delete", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        var confirm = MessageBox.Show(this, $"Permanently delete zone {z.ZoneCode}?", "Confirm Delete",
            MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (confirm != DialogResult.Yes) return;
        var result = _repo.DeleteZone(z.ZoneCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Delete", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadZones);
    }

    private void NewZone()
    {
        using var form = new EditZoneSectionForm("New Zone", "Zone code", "Zone name");
        if (form.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.CreateZone(form.Code, form.DisplayName, form.Description);
        if (!result.Success)
        { MessageBox.Show(this, result.FriendlyMessage, "Cannot Create", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        Execute(LoadZones);
    }

    private void EditSelected()
    {
        if (Selected() is not ZoneDto z) return;
        using var form = new EditZoneSectionForm("Edit Zone", "Zone code", "Zone name", z.ZoneCode, z.ZoneName, z.Description);
        if (form.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.UpdateZone(z.ZoneCode, form.DisplayName, form.Description, form.ClearDescription);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Update", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadZones);
    }

    private void DeactivateSelected()
    {
        if (Selected() is not ZoneDto z) return;
        var confirm = MessageBox.Show(this,
            $"Deactivate zone {z.ZoneCode}?\n\nExisting bin assignments are preserved.",
            "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (confirm != DialogResult.Yes) return;
        var result = _repo.DeactivateZone(z.ZoneCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Deactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadZones);
    }

    private void ReactivateSelected()
    {
        if (Selected() is not ZoneDto z) return;
        var result = _repo.ReactivateZone(z.ZoneCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Reactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadZones);
    }

    private void ToggleInactive()
    {
        _showInactive = !_showInactive;
        Execute(LoadZones);
    }

    private ZoneDto? Selected() =>
        _dgv.SelectedRows.Count == 1 && _dgv.SelectedRows[0].DataBoundItem is ZoneDto z ? z : null;

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
