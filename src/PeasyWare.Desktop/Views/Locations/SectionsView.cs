using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class SectionsView : BaseView, IToolbarAware
{
    private readonly ISectionRepository            _repo;
    private readonly ILocationQueryRepository      _locationQuery;
    private readonly ILocationCommandRepository    _locationCommand;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnNew;
    private ToolStripButton? _btnEdit;
    private ToolStripButton? _btnAssign;
    private ToolStripButton? _btnDeactivate;
    private ToolStripButton? _btnReactivate;
    private ToolStripButton? _btnShowInactive;

    private bool _showInactive = false;

    private readonly DataGridView _dgv = new();

    public SectionsView(
        ISectionRepository         repo,
        ILocationQueryRepository   locationQuery,
        ILocationCommandRepository locationCommand)
    {
        _repo            = repo;
        _locationQuery   = locationQuery;
        _locationCommand = locationCommand;
        ConfigureGrid(_dgv);
        EnableDoubleBuffering(_dgv);
        _dgv.Dock              = DockStyle.Fill;
        _dgv.SelectionChanged += (_, _) => UpdateToolbarState();
        _dgv.CellDoubleClick  += (_, e) => { if (e.RowIndex >= 0) Execute(EditSelected); };
        Controls.Add(_dgv);
        AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Load += (_, _) => Execute(LoadSections);
    }

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadSections);

        _btnNew = new ToolStripButton("New section") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewSection);

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

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Code",        DataPropertyName = nameof(SectionDto.SectionCode),        FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Name",        DataPropertyName = nameof(SectionDto.SectionName),        FillWeight = 14 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = nameof(SectionDto.Description),        FillWeight = 24 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Total bins",  DataPropertyName = nameof(SectionDto.TotalBins),          FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active bins", DataPropertyName = nameof(SectionDto.ActiveBins),         FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active",      DataPropertyName = nameof(SectionDto.IsActive),           FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created",     DataPropertyName = nameof(SectionDto.CreatedAt),          FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created by",  DataPropertyName = nameof(SectionDto.CreatedByUsername),  FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Updated",     DataPropertyName = nameof(SectionDto.UpdatedAt),          FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy HH:mm" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Updated by",  DataPropertyName = nameof(SectionDto.UpdatedByUsername),  FillWeight = 6  });

        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not SectionDto s) return;
            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = s.IsActive
                ? System.Drawing.SystemColors.Window
                : Color.FromArgb(235, 235, 235);
            dgv.Rows[e.RowIndex].DefaultCellStyle.ForeColor = s.IsActive
                ? System.Drawing.SystemColors.WindowText
                : Color.Gray;
        };
    }

    private void LoadSections()
    {
        _dgv.DataSource = null;
        _dgv.DataSource = _repo.GetSections(includeInactive: _showInactive).ToList();
        if (_btnShowInactive is not null)
            _btnShowInactive.Text = _showInactive ? "Hide inactive" : "Show inactive";
        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        var s = Selected();
        if (_btnEdit       is not null) _btnEdit.Enabled       = s is not null;
        if (_btnAssign     is not null) _btnAssign.Enabled     = s is not null;
        if (_btnDeactivate is not null) _btnDeactivate.Enabled = s is not null &&  s.IsActive;
        if (_btnReactivate is not null) _btnReactivate.Enabled = s is not null && !s.IsActive;
    }

    private void AssignToLocations()
    {
        if (Selected() is not SectionDto section) return;

        using var form = new AssignLocationsForm(
            $"Assign locations to section: {section.SectionCode} — {section.SectionName}",
            "Assign",
            _locationQuery,
            binCodes =>
            {
                var result = _locationCommand.AssignBinsToSection(section.SectionCode, binCodes);
                return result.Success ? null : result.FriendlyMessage;
            });

        form.ShowDialog(this);
        Execute(LoadSections);
    }

    private void NewSection()
    {
        using var form = new EditZoneSectionForm("New Section", "Section code", "Section name");
        if (form.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.CreateSection(form.Code, form.DisplayName, form.Description);
        if (!result.Success)
        { MessageBox.Show(this, result.FriendlyMessage, "Cannot Create", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
        Execute(LoadSections);
    }

    private void EditSelected()
    {
        if (Selected() is not SectionDto s) return;
        using var form = new EditZoneSectionForm("Edit Section", "Section code", "Section name", s.SectionCode, s.SectionName, s.Description);
        if (form.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.UpdateSection(s.SectionCode, form.DisplayName, form.Description, form.ClearDescription);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Update", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadSections);
    }

    private void DeactivateSelected()
    {
        if (Selected() is not SectionDto s) return;
        var confirm = MessageBox.Show(this,
            $"Deactivate section {s.SectionCode}?\n\nExisting bin assignments are preserved.",
            "Confirm", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
        if (confirm != DialogResult.Yes) return;
        var result = _repo.DeactivateSection(s.SectionCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Deactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadSections);
    }

    private void ReactivateSelected()
    {
        if (Selected() is not SectionDto s) return;
        var result = _repo.ReactivateSection(s.SectionCode);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Reactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadSections);
    }

    private void ToggleInactive()
    {
        _showInactive = !_showInactive;
        Execute(LoadSections);
    }

    private SectionDto? Selected() =>
        _dgv.SelectedRows.Count == 1 && _dgv.SelectedRows[0].DataBoundItem is SectionDto s ? s : null;

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
