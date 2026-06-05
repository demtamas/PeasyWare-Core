using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

/// <summary>Generic create/edit form for zones and sections.</summary>
public sealed class EditZoneSectionForm : Form
{
    private readonly TextBox _txtCode  = new();
    private readonly TextBox _txtName  = new();
    private readonly TextBox _txtDesc  = new();
    private readonly CheckBox _chkClearDesc = new() { Text = "Clear description", AutoSize = true };

    private readonly bool _isEdit;

    public string  Code             => _txtCode.Text.Trim().ToUpperInvariant();
    public string  DisplayName      => _txtName.Text.Trim();
    public string? Description      => string.IsNullOrWhiteSpace(_txtDesc.Text) ? null : _txtDesc.Text.Trim();
    public bool    ClearDescription => _chkClearDesc.Checked;

    public EditZoneSectionForm(
        string  title,
        string  codeLabel,
        string  nameLabel,
        string? currentCode = null,
        string? currentName = null,
        string? currentDesc = null)
    {
        _isEdit = currentCode is not null;

        Text            = title;
        Size            = new Size(400, 240);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 4,
            Padding     = new Padding(12, 12, 12, 0)
        };
        for (int i = 0; i < 4; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 30f));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _txtCode.Text    = currentCode ?? "";
        _txtName.Text    = currentName ?? "";
        _txtDesc.Text    = currentDesc ?? "";
        _txtDesc.PlaceholderText = "Optional description";

        // Code not editable on update (it's the lookup key)
        if (_isEdit)
        {
            _txtCode.Enabled   = false;
            _txtCode.BackColor = Color.FromArgb(245, 245, 245);
        }

        AddRow(table, 0, $"{codeLabel} *", _txtCode);
        AddRow(table, 1, $"{nameLabel} *", _txtName);
        AddRow(table, 2, "Description",    _txtDesc);

        if (_isEdit)
        {
            var lblClear = new Label { Dock = DockStyle.Fill };
            table.Controls.Add(lblClear, 0, 3);
            _chkClearDesc.Dock = DockStyle.Fill;
            table.Controls.Add(_chkClearDesc, 1, 3);
        }

        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 46, Padding = new Padding(12, 8, 0, 0) };
        var btnSave   = new Button { Text = _isEdit ? "Save" : "Create", Width = 80, Height = 28, Location = new Point(12, 8) };
        var btnCancel = new Button { Text = "Cancel", Width = 80, Height = 28, Location = new Point(100, 8), DialogResult = DialogResult.Cancel };

        btnSave.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(_txtCode.Text))
            { MessageBox.Show(this, $"{codeLabel} is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            if (string.IsNullOrWhiteSpace(_txtName.Text))
            { MessageBox.Show(this, $"{nameLabel} is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }
            DialogResult = DialogResult.OK;
        };

        pnlFooter.Controls.AddRange([btnSave, btnCancel]);
        Controls.Add(table);
        Controls.Add(pnlFooter);
        AcceptButton = btnSave;
        CancelButton = btnCancel;
    }

    private static void AddRow(TableLayoutPanel t, int row, string label, Control ctrl)
    {
        var lbl = new Label { Text = label, Dock = DockStyle.Fill, TextAlign = System.Drawing.ContentAlignment.MiddleRight, Font = new Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8.5f) };
        ctrl.Dock = DockStyle.Fill;
        t.Controls.Add(lbl,  0, row);
        t.Controls.Add(ctrl, 1, row);
    }
}
