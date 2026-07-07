using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Settings;

public sealed class ClientsView : BaseView, IToolbarAware
{
    private readonly IClientRepository _repo;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnNew;
    private ToolStripButton? _btnEdit;
    private ToolStripButton? _btnDeactivate;
    private ToolStripButton? _btnReactivate;
    private ToolStripButton? _btnShowInactive;

    private bool _showInactive;
    private readonly DataGridView _dgv = new();

    public ClientsView(IClientRepository repo)
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
        Load += (_, _) => Execute(LoadClients);
    }

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadClients);

        _btnNew = new ToolStripButton("New client") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnNew.Click += Wrap(NewClient);

        _btnEdit = new ToolStripButton("Edit") { DisplayStyle = ToolStripItemDisplayStyle.Text, Enabled = false };
        _btnEdit.Click += Wrap(EditSelected);

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
        dgv.BackgroundColor       = SystemColors.Window;
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Client name",      DataPropertyName = nameof(ClientDto.ClientName),            FillWeight = 20 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Timeout (min)",    DataPropertyName = nameof(ClientDto.SessionTimeoutMinutes),  FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Max sessions",     DataPropertyName = nameof(ClientDto.MaxConcurrentSessions),  FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active",           DataPropertyName = nameof(ClientDto.IsActive),               FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description",      DataPropertyName = nameof(ClientDto.Description),            FillWeight = 30 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created",          DataPropertyName = nameof(ClientDto.CreatedAt),              FillWeight = 8, DefaultCellStyle = new DataGridViewCellStyle { Format = "dd/MM/yyyy" } });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Created by",       DataPropertyName = nameof(ClientDto.CreatedByUsername),      FillWeight = 8  });

        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not ClientDto c) return;
            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = c.IsActive ? SystemColors.Window : Color.FromArgb(235, 235, 235);
            dgv.Rows[e.RowIndex].DefaultCellStyle.ForeColor = c.IsActive ? SystemColors.WindowText : Color.Gray;
        };

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not ClientDto c) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName == nameof(ClientDto.SessionTimeoutMinutes) && e.Value == null)
                e.Value = "— global —";
            if (dgv.Columns[e.ColumnIndex].DataPropertyName == nameof(ClientDto.MaxConcurrentSessions) && e.Value == null)
                e.Value = "Unlimited";
        };
    }

    private void LoadClients()
    {
        _dgv.DataSource = null;
        _dgv.DataSource = _repo.GetClients(includeInactive: _showInactive).ToList();
        if (_btnShowInactive is not null)
            _btnShowInactive.Text = _showInactive ? "Hide inactive" : "Show inactive";
        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        var c = Selected();
        if (_btnEdit       is not null) _btnEdit.Enabled       = c is not null;
        if (_btnDeactivate is not null) _btnDeactivate.Enabled = c is not null &&  c.IsActive;
        if (_btnReactivate is not null) _btnReactivate.Enabled = c is not null && !c.IsActive;
    }

    private void NewClient()
    {
        using var form = new ClientEditForm("", null, null, null);
        // For New, we need the client name — use a simple input approach
        using var nameDlg = new Form
        {
            Text = "New Client Application", Size = new System.Drawing.Size(380, 130),
            FormBorderStyle = FormBorderStyle.FixedDialog, MaximizeBox = false, MinimizeBox = false,
            StartPosition = FormStartPosition.CenterParent
        };
        var lbl = new Label { Text = "Client name:", Left = 14, Top = 20, Width = 100, TextAlign = System.Drawing.ContentAlignment.MiddleRight };
        var txt = new TextBox { Left = 120, Top = 18, Width = 220, PlaceholderText = "e.g. PeasyWare.Mobile" };
        var ok  = new Button { Text = "Next →", Left = 180, Top = 52, Width = 80, Height = 26, DialogResult = DialogResult.OK };
        var can = new Button { Text = "Cancel", Left = 268, Top = 52, Width = 72, Height = 26, DialogResult = DialogResult.Cancel };
        nameDlg.Controls.AddRange(new Control[] { lbl, txt, ok, can });
        nameDlg.AcceptButton = ok; nameDlg.CancelButton = can;

        if (nameDlg.ShowDialog(this) != DialogResult.OK || string.IsNullOrWhiteSpace(txt.Text)) return;

        using var editDlg = new ClientEditForm(txt.Text.Trim(), null, null, null);
        if (editDlg.ShowDialog(this) != DialogResult.OK) return;

        var result = _repo.CreateClient(txt.Text.Trim(), editDlg.NewTimeout, editDlg.NewMaxSessions, editDlg.NewDescription);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Create", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadClients);
    }

    private void EditSelected()
    {
        if (Selected() is not ClientDto c) return;
        using var dlg = new ClientEditForm(c.ClientName, c.SessionTimeoutMinutes, c.MaxConcurrentSessions, c.Description);
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        var result = _repo.UpdateClient(c.ClientName,
            sessionTimeoutMinutes: dlg.NewTimeout,    clearTimeout:     dlg.ClearTimeout,
            maxConcurrentSessions: dlg.NewMaxSessions, clearMaxSessions: dlg.ClearMaxSessions,
            description: dlg.NewDescription,           clearDesc:        string.IsNullOrEmpty(dlg.NewDescription) && !dlg.ClearTimeout);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Update", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadClients);
    }

    private void DeactivateSelected()
    {
        if (Selected() is not ClientDto c) return;
        if (MessageBox.Show(this, $"Deactivate client {c.ClientName}?", "Confirm",
            MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return;
        var result = _repo.DeactivateClient(c.ClientName);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Deactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadClients);
    }

    private void ReactivateSelected()
    {
        if (Selected() is not ClientDto c) return;
        var result = _repo.ReactivateClient(c.ClientName);
        if (!result.Success)
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Reactivate", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        Execute(LoadClients);
    }

    private void ToggleInactive() { _showInactive = !_showInactive; Execute(LoadClients); }

    private ClientDto? Selected() =>
        _dgv.SelectedRows.Count == 1 && _dgv.SelectedRows[0].DataBoundItem is ClientDto c ? c : null;

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
