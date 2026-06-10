using PeasyWare.Application.Dto;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Users;

public sealed partial class AddUserForm : Form
{
    // --------------------------------------------------
    // Controls
    // --------------------------------------------------
    private readonly TextBox   _txtUsername        = new() { PlaceholderText = "e.g. jsmith" };
    private readonly TextBox   _txtDisplayName     = new() { PlaceholderText = "e.g. John Smith" };
    private readonly TextBox   _txtEmail           = new() { PlaceholderText = "e.g. jsmith@company.com" };
    private readonly ComboBox  _cmbRole            = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox   _txtPassword        = new() { UseSystemPasswordChar = true };
    private readonly TextBox   _txtConfirm         = new() { UseSystemPasswordChar = true };
    private readonly CheckBox  _chkShowPassword    = new() { Text = "Show passwords", AutoSize = true };
    private readonly Label     _lblMatch           = new() { AutoSize = true, ForeColor = Color.DarkRed, Text = "" };
    private readonly Button    _btnSave            = new() { Text = "Add user",  Width = 90, Height = 28 };
    private readonly Button    _btnClear           = new() { Text = "Clear",     Width = 80, Height = 28 };
    private readonly Button    _btnCancel          = new() { Text = "Cancel",    Width = 80, Height = 28,
                                                             DialogResult = DialogResult.Cancel };

    // --------------------------------------------------
    // Public properties consumed by caller
    // --------------------------------------------------
    public string Username    => _txtUsername.Text.Trim();
    public string DisplayName => _txtDisplayName.Text.Trim();
    public string Email       => _txtEmail.Text.Trim();
    public string Password    => _txtPassword.Text;
    public string RoleName    => _cmbRole.SelectedItem is RoleDto r ? r.RoleName : "";

    // --------------------------------------------------
    // Constructor
    // --------------------------------------------------
    public AddUserForm(IEnumerable<RoleDto> roles)
    {
        Text            = "Add User";
        Size            = new Size(480, 400);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        _cmbRole.DisplayMember = nameof(RoleDto.RoleName);
        _cmbRole.DataSource    = roles.ToList();
        if (_cmbRole.Items.Count > 0) _cmbRole.SelectedIndex = 0;

        BuildLayout();

        // Validation hooks
        foreach (Control c in new Control[] { _txtUsername, _txtDisplayName, _txtEmail, _txtPassword, _txtConfirm })
            c.TextChanged += (_, _) => UpdateState();
        _cmbRole.SelectedIndexChanged += (_, _) => UpdateState();
        _chkShowPassword.CheckedChanged += (_, e) =>
        {
            _txtPassword.UseSystemPasswordChar = !_chkShowPassword.Checked;
            _txtConfirm.UseSystemPasswordChar  = !_chkShowPassword.Checked;
        };

        _btnSave.Click   += (_, _) => { DialogResult = DialogResult.OK; };
        _btnClear.Click  += (_, _) => ClearAll();
        _btnCancel.Click += (_, _) => Close();

        AcceptButton = _btnSave;
        CancelButton = _btnCancel;

        UpdateState();
    }

    // --------------------------------------------------
    // Layout
    // --------------------------------------------------
    private void BuildLayout()
    {
        // Header bar
        var header = new Panel
        {
            Dock      = DockStyle.Top,
            Height    = 40,
            BackColor = Color.FromArgb(45, 45, 48)
        };
        header.Controls.Add(new Label
        {
            Text      = "New User",
            Dock      = DockStyle.Fill,
            ForeColor = Color.White,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            Padding   = new Padding(14, 10, 0, 0)
        });

        // Table
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 8,
            Padding     = new Padding(12, 10, 12, 0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (int i = 0; i < 8; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 34f));

        AddRow(table, 0, "Username *",         _txtUsername);
        AddRow(table, 1, "Full name *",        _txtDisplayName);
        AddRow(table, 2, "Email *",            _txtEmail);
        AddRow(table, 3, "Role *",             _cmbRole);
        AddRow(table, 4, "Password *",         _txtPassword);
        AddRow(table, 5, "Confirm password *", _txtConfirm);

        // Show password checkbox + match label in one row
        _chkShowPassword.Dock   = DockStyle.Fill;
        _lblMatch.Dock          = DockStyle.Fill;
        _lblMatch.TextAlign     = ContentAlignment.MiddleLeft;

        table.Controls.Add(_chkShowPassword, 1, 6);
        table.Controls.Add(_lblMatch,        1, 7);

        // Footer
        var footer = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(12, 10, 12, 0) };
        _btnSave.Enabled  = false;
        _btnSave.Location = new Point(12, 10);
        _btnClear.Location = new Point(110, 10);
        _btnCancel.Location = new Point(198, 10);
        footer.Controls.AddRange(new Control[] { _btnSave, _btnClear, _btnCancel });

        Controls.Add(table);
        Controls.Add(footer);
        Controls.Add(header);
    }

    private static void AddRow(TableLayoutPanel t, int row, string label, Control ctrl)
    {
        var lbl = new Label
        {
            Text      = label,
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleRight,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f)
        };
        ctrl.Dock = DockStyle.Fill;
        t.Controls.Add(lbl,  0, row);
        t.Controls.Add(ctrl, 1, row);
    }

    // --------------------------------------------------
    // Validation
    // --------------------------------------------------
    private void UpdateState()
    {
        var passwordsMatch = _txtPassword.Text == _txtConfirm.Text;
        var passwordFilled = _txtPassword.TextLength > 0;

        _lblMatch.Text = passwordFilled
            ? (passwordsMatch ? "" : "Passwords do not match")
            : "";
        _lblMatch.ForeColor = Color.DarkRed;

        _btnSave.Enabled =
            !string.IsNullOrWhiteSpace(Username)     &&
            !string.IsNullOrWhiteSpace(DisplayName)  &&
            !string.IsNullOrWhiteSpace(Email)        &&
            !string.IsNullOrWhiteSpace(RoleName)     &&
            passwordFilled                           &&
            passwordsMatch;
    }

    // --------------------------------------------------
    // Public helpers
    // --------------------------------------------------
    private void ClearAll()
    {
        _txtUsername.Clear();
        _txtDisplayName.Clear();
        _txtEmail.Clear();
        _txtPassword.Clear();
        _txtConfirm.Clear();
        if (_cmbRole.Items.Count > 0) _cmbRole.SelectedIndex = 0;
        _txtUsername.Focus();
    }

    public void ResetAfterFailure(string message)
    {
        MessageBox.Show(message, "User creation failed",
            MessageBoxButtons.OK, MessageBoxIcon.Warning);
        _txtPassword.Clear();
        _txtConfirm.Clear();
        _btnSave.Enabled = false;
        _txtUsername.Focus();
    }

    public void RefreshRoles(IEnumerable<RoleDto> roles)
    {
        var current = RoleName;
        _cmbRole.DataSource    = null;
        _cmbRole.DisplayMember = nameof(RoleDto.RoleName);
        _cmbRole.DataSource    = roles.ToList();

        if (_cmbRole.Items.Count == 0) return;
        for (int i = 0; i < _cmbRole.Items.Count; i++)
        {
            if (_cmbRole.Items[i] is RoleDto r && r.RoleName == current)
            { _cmbRole.SelectedIndex = i; return; }
        }
        _cmbRole.SelectedIndex = 0;
    }
}
