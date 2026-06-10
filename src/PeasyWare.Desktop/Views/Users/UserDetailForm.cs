using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Users;

/// <summary>
/// Shows user details as a read-only property card.
/// Toggle Edit to update DisplayName, Email and Role.
/// </summary>
public sealed class UserDetailForm : Form
{
    private readonly UserSummaryDto         _user;
    private readonly IUserCommandRepository _commandRepo;
    private readonly IUserQueryRepository   _queryRepo;

    // Read-only display labels (always visible)
    private readonly Label _lblUsername       = new();
    private readonly Label _lblDisplayName    = new();
    private readonly Label _lblEmail          = new();
    private readonly Label _lblRole           = new();
    private readonly Label _lblActive         = new();
    private readonly Label _lblOnline         = new();
    private readonly Label _lblLastSeen       = new();
    private readonly Label _lblFailedAttempts = new();
    private readonly Label _lblLockout        = new();
    private readonly Label _lblCreatedAt      = new();

    // Editable controls (hidden until Edit mode)
    private readonly TextBox  _txtDisplayName = new();
    private readonly TextBox  _txtEmail       = new();
    private readonly ComboBox _cmbRole        = new() { DropDownStyle = ComboBoxStyle.DropDownList };

    // Footer buttons
    private readonly Button _btnEdit   = new() { Text = "✏  Edit", Width = 90, Height = 28 };
    private readonly Button _btnSave   = new() { Text = "Save",    Width = 80, Height = 28, Visible = false };
    private readonly Button _btnCancel = new() { Text = "Cancel",  Width = 80, Height = 28, Visible = false };
    private readonly Button _btnClose  = new() { Text = "Close",   Width = 80, Height = 28, DialogResult = DialogResult.Cancel };

    // Original values for cancel revert
    private string _origDisplayName = "";
    private string _origEmail       = "";
    private string _origRole        = "";

    public bool UserWasChanged { get; private set; }

    // ==========================================================
    // Constructor
    // ==========================================================

    public UserDetailForm(
        UserSummaryDto          user,
        IUserCommandRepository  commandRepo,
        IUserQueryRepository    queryRepo)
    {
        _user        = user;
        _commandRepo = commandRepo;
        _queryRepo   = queryRepo;

        Text            = $"User \u2014 {user.Username}";
        Size            = new Size(500, 480);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        _cmbRole.DisplayMember = nameof(RoleDto.RoleName);
        _cmbRole.DataSource    = queryRepo.GetRoles().ToList();

        BuildLayout();
        PopulateValues();

        _btnEdit.Click   += (_, _) => EnterEditMode();
        _btnSave.Click   += (_, _) => SaveChanges();
        _btnCancel.Click += (_, _) => CancelEdit();
        _btnClose.Click  += (_, _) => Close();

        CancelButton = _btnClose;
    }

    // ==========================================================
    // Layout
    // ==========================================================

    private void BuildLayout()
    {
        // Dark header
        var header = new Panel { Dock = DockStyle.Top, Height = 42, BackColor = Color.FromArgb(45, 45, 48) };
        header.Controls.Add(new Label
        {
            Text      = _user.Username,
            Dock      = DockStyle.Fill,
            ForeColor = Color.White,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            Padding   = new Padding(14, 10, 0, 0)
        });

        // Table: caption col (fixed) | value col (fill)
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 10,
            Padding     = new Padding(14, 10, 14, 0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 136));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (int i = 0; i < 10; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 32f));

        // Row 0 — Username (always read-only)
        AddRow(table, 0, "Username",        ValueCell(_lblUsername));

        // Row 1 — Display name (editable)
        AddRow(table, 1, "Display name",    EditableCell(_lblDisplayName, _txtDisplayName));

        // Row 2 — Email (editable)
        AddRow(table, 2, "Email",           EditableCell(_lblEmail, _txtEmail));

        // Row 3 — Role (editable)
        AddRow(table, 3, "Role",            EditableCell(_lblRole, _cmbRole));

        // Row 4-9 — Read-only status fields
        AddRow(table, 4, "Active",          ValueCell(_lblActive));
        AddRow(table, 5, "Online",          ValueCell(_lblOnline));
        AddRow(table, 6, "Last seen",       ValueCell(_lblLastSeen));
        AddRow(table, 7, "Failed attempts", ValueCell(_lblFailedAttempts));
        AddRow(table, 8, "Lockout until",   ValueCell(_lblLockout));
        AddRow(table, 9, "Created",         ValueCell(_lblCreatedAt));

        // Footer
        var footer = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(14, 10, 0, 0) };
        _btnEdit.Location   = new Point(14,  10);
        _btnSave.Location   = new Point(14,  10);
        _btnCancel.Location = new Point(102, 10);
        _btnClose.Location  = new Point(210, 10);
        footer.Controls.AddRange(new Control[] { _btnEdit, _btnSave, _btnCancel, _btnClose });

        Controls.Add(table);
        Controls.Add(footer);
        Controls.Add(header);
    }

    /// <summary>Cell with a single always-visible label.</summary>
    private static Panel ValueCell(Label lbl)
    {
        lbl.Dock      = DockStyle.Fill;
        lbl.TextAlign = ContentAlignment.MiddleLeft;
        lbl.Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f);

        var panel = new Panel { Dock = DockStyle.Fill };
        panel.Controls.Add(lbl);
        return panel;
    }

    /// <summary>Cell that contains both a read-only label and an editable control.
    /// Only one is visible at a time.</summary>
    private static Panel EditableCell(Label lbl, Control edit)
    {
        lbl.Dock      = DockStyle.Fill;
        lbl.TextAlign = ContentAlignment.MiddleLeft;
        lbl.Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f);

        edit.Dock    = DockStyle.Fill;
        edit.Visible = false;

        var panel = new Panel { Dock = DockStyle.Fill };
        panel.Controls.Add(edit);
        panel.Controls.Add(lbl);   // added second so it's on top in read mode
        return panel;
    }

    private static void AddRow(TableLayoutPanel t, int row, string caption, Control valuePanel)
    {
        var lbl = new Label
        {
            Text      = caption,
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleRight,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f, FontStyle.Bold),
            ForeColor = Color.FromArgb(60, 60, 90)
        };
        t.Controls.Add(lbl,        0, row);
        t.Controls.Add(valuePanel, 1, row);
    }

    // ==========================================================
    // Populate
    // ==========================================================

    private void PopulateValues()
    {
        _lblUsername.Text       = _user.Username;
        _lblDisplayName.Text    = _user.DisplayName;
        _txtDisplayName.Text    = _user.DisplayName;
        _lblEmail.Text          = _user.Email ?? "—";
        _txtEmail.Text          = _user.Email ?? "";
        _lblRole.Text           = _user.RoleName;
        _lblActive.Text         = _user.IsActive ? "✔  Active"  : "✘  Inactive";
        _lblActive.ForeColor    = _user.IsActive ? Color.DarkGreen : Color.DarkRed;
        _lblOnline.Text         = _user.IsOnline ? "●  Online"  : "○  Offline";
        _lblOnline.ForeColor    = _user.IsOnline ? Color.SeaGreen  : Color.Gray;
        _lblLastSeen.Text       = _user.LastLastSeen?.ToString("dd/MM/yyyy HH:mm") ?? "—";
        _lblFailedAttempts.Text = _user.FailedAttempts.ToString();
        _lblFailedAttempts.ForeColor = _user.FailedAttempts > 2 ? Color.DarkOrange : SystemColors.WindowText;
        _lblLockout.Text        = _user.IsLockedOut
            ? $"Until {_user.LockoutUntil:dd/MM/yyyy HH:mm}"
            : "—";
        _lblLockout.ForeColor   = _user.IsLockedOut ? Color.DarkRed : SystemColors.WindowText;
        _lblCreatedAt.Text      = _user.CreatedAt.ToString("dd/MM/yyyy HH:mm");

        // Pre-select current role
        for (int i = 0; i < _cmbRole.Items.Count; i++)
            if (_cmbRole.Items[i] is RoleDto r && r.RoleName == _user.RoleName)
            { _cmbRole.SelectedIndex = i; break; }
    }

    // ==========================================================
    // Edit mode toggle
    // ==========================================================

    private void EnterEditMode()
    {
        _origDisplayName = _txtDisplayName.Text;
        _origEmail       = _txtEmail.Text;
        _origRole        = _cmbRole.SelectedItem is RoleDto r ? r.RoleName : "";

        // Swap: hide labels, show editable controls
        _lblDisplayName.Visible = false;  _txtDisplayName.Visible = true;
        _lblEmail.Visible       = false;  _txtEmail.Visible       = true;
        _lblRole.Visible        = false;  _cmbRole.Visible        = true;

        _btnEdit.Visible   = false;
        _btnSave.Visible   = true;
        _btnCancel.Visible = true;
        _btnClose.Visible  = false;

        _txtDisplayName.Focus();
        _txtDisplayName.SelectAll();
    }

    private void LeaveEditMode()
    {
        _txtDisplayName.Visible = false;  _lblDisplayName.Visible = true;
        _txtEmail.Visible       = false;  _lblEmail.Visible       = true;
        _cmbRole.Visible        = false;  _lblRole.Visible        = true;

        _btnSave.Visible   = false;
        _btnCancel.Visible = false;
        _btnEdit.Visible   = true;
        _btnClose.Visible  = true;
    }

    private void CancelEdit()
    {
        _txtDisplayName.Text = _origDisplayName;
        _txtEmail.Text       = _origEmail;
        for (int i = 0; i < _cmbRole.Items.Count; i++)
            if (_cmbRole.Items[i] is RoleDto r && r.RoleName == _origRole)
            { _cmbRole.SelectedIndex = i; break; }

        LeaveEditMode();
    }

    // ==========================================================
    // Save
    // ==========================================================

    private void SaveChanges()
    {
        var newDisplay = _txtDisplayName.Text.Trim();
        var newEmail   = _txtEmail.Text.Trim();
        var newRole    = _cmbRole.SelectedItem is RoleDto r ? r.RoleName : _origRole;

        if (string.IsNullOrWhiteSpace(newDisplay))
        {
            MessageBox.Show(this, "Display name is required.", "Validation",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            _txtDisplayName.Focus();
            return;
        }

        var changedDisplay = newDisplay != _origDisplayName ? newDisplay : null;
        var changedEmail   = newEmail   != _origEmail       ? newEmail   : null;
        var changedRole    = newRole    != _origRole         ? newRole    : null;

        if (changedDisplay == null && changedEmail == null && changedRole == null)
        { LeaveEditMode(); return; }

        var result = _commandRepo.UpdateUser(
            _user.UserId,
            displayName: changedDisplay,
            email:       changedEmail,
            roleName:    changedRole);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Save",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        // Refresh the read-only labels with saved values
        _lblDisplayName.Text = newDisplay;
        _lblEmail.Text       = string.IsNullOrEmpty(newEmail) ? "—" : newEmail;
        _lblRole.Text        = newRole;

        UserWasChanged = true;
        LeaveEditMode();
    }
}
