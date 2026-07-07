using System;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Settings;

/// <summary>
/// Simple edit form for a single auth.clients row.
/// </summary>
public sealed class ClientEditForm : Form
{
    private readonly TextBox        _txtName        = new() { ReadOnly = true };
    private readonly NumericUpDown  _nudTimeout     = new() { Minimum = 0, Maximum = 9999, DecimalPlaces = 0 };
    private readonly CheckBox       _chkClearTimeout = new() { Text = "Use global (clear override)" };
    private readonly NumericUpDown  _nudMaxSessions = new() { Minimum = 0, Maximum = 999, DecimalPlaces = 0 };
    private readonly CheckBox       _chkClearMax    = new() { Text = "Unlimited (clear override)" };
    private readonly TextBox        _txtDescription = new();
    private readonly Button         _btnSave        = new() { Text = "Save",   Width = 80, Height = 28, DialogResult = DialogResult.OK };
    private readonly Button         _btnCancel      = new() { Text = "Cancel", Width = 80, Height = 28, DialogResult = DialogResult.Cancel };

    public int?    NewTimeout       => _chkClearTimeout.Checked ? null : (int)_nudTimeout.Value;
    public bool    ClearTimeout     => _chkClearTimeout.Checked;
    public int?    NewMaxSessions   => _chkClearMax.Checked     ? null : (int)_nudMaxSessions.Value;
    public bool    ClearMaxSessions => _chkClearMax.Checked;
    public string? NewDescription   => string.IsNullOrWhiteSpace(_txtDescription.Text) ? null : _txtDescription.Text.Trim();

    public ClientEditForm(
        string  clientName,
        int?    sessionTimeoutMinutes,
        int?    maxConcurrentSessions,
        string? description)
    {
        Text            = $"Edit Client — {clientName}";
        Size            = new System.Drawing.Size(460, 330);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        // Populate
        _txtName.Text = clientName;
        if (sessionTimeoutMinutes.HasValue)
        {
            _nudTimeout.Value = sessionTimeoutMinutes.Value;
            _chkClearTimeout.Checked = false;
        }
        else
        {
            _nudTimeout.Value        = 30;
            _chkClearTimeout.Checked = true;
        }

        if (maxConcurrentSessions.HasValue)
        {
            _nudMaxSessions.Value   = maxConcurrentSessions.Value;
            _chkClearMax.Checked    = false;
        }
        else
        {
            _nudMaxSessions.Value   = 1;
            _chkClearMax.Checked    = true;
        }

        _txtDescription.Text = description ?? "";

        // Layout
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 7,
            Padding     = new System.Windows.Forms.Padding(14, 12, 14, 0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (int i = 0; i < 7; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 34f));

        AddRow(table, 0, "Client name",           _txtName);
        AddRow(table, 1, "Session timeout (min)", _nudTimeout);
        table.Controls.Add(new Label(), 0, 2);
        _chkClearTimeout.Dock = DockStyle.Fill;
        table.Controls.Add(_chkClearTimeout, 1, 2);
        AddRow(table, 3, "Max sessions",          _nudMaxSessions);
        table.Controls.Add(new Label(), 0, 4);
        _chkClearMax.Dock = DockStyle.Fill;
        table.Controls.Add(_chkClearMax, 1, 4);
        AddRow(table, 5, "Description",           _txtDescription);

        _nudTimeout.Dock     = DockStyle.Fill;
        _nudMaxSessions.Dock = DockStyle.Fill;
        _txtDescription.Dock = DockStyle.Fill;

        _chkClearTimeout.CheckedChanged += (_, _) => _nudTimeout.Enabled     = !_chkClearTimeout.Checked;
        _chkClearMax.CheckedChanged     += (_, _) => _nudMaxSessions.Enabled = !_chkClearMax.Checked;
        _nudTimeout.Enabled     = !_chkClearTimeout.Checked;
        _nudMaxSessions.Enabled = !_chkClearMax.Checked;

        var footer = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new System.Windows.Forms.Padding(0, 10, 14, 0) };
        _btnSave.Dock   = DockStyle.Right;
        _btnCancel.Dock = DockStyle.Right;
        footer.Controls.AddRange(new Control[] { _btnCancel, _btnSave });

        Controls.Add(table);
        Controls.Add(footer);
        AcceptButton = _btnSave;
        CancelButton = _btnCancel;
    }

    private static void AddRow(TableLayoutPanel t, int row, string label, Control ctrl)
    {
        var lbl = new Label
        {
            Text      = label,
            Dock      = DockStyle.Fill,
            TextAlign = System.Drawing.ContentAlignment.MiddleRight,
            Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8.5f, System.Drawing.FontStyle.Bold),
            ForeColor = System.Drawing.Color.FromArgb(60, 60, 90)
        };
        t.Controls.Add(lbl,  0, row);
        t.Controls.Add(ctrl, 1, row);
    }
}
