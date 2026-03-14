using PeasyWare.Application.Dto;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Users;

public partial class AddUserForm : Form
{
    public string Username => txtUsername.Text.Trim();
    public string DisplayName => txtDisplayName.Text.Trim();
    public string Email => txtEmail.Text.Trim();

    // 🔑 IMPORTANT: this is now the canonical value passed to SQL
    public string RoleName =>
    cmbRole.SelectedItem is RoleDto role
        ? role.RoleName
        : "";

    public string Password => txtPassword.Text;

    public AddUserForm(IEnumerable<RoleDto> roles)
    {
        InitializeComponent();

        Text = "Add User";
        StartPosition = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        btnSave.Enabled = false;

        txtPassword.UseSystemPasswordChar = true;
        txtConfirmPassword.UseSystemPasswordChar = true;

        // --------------------------------------------------
        // Role combo (CORRECT binding)
        // --------------------------------------------------

        cmbRole.DropDownStyle = ComboBoxStyle.DropDownList;
        cmbRole.DisplayMember = nameof(RoleDto.RoleName);
        //cmbRole.ValueMember = nameof(RoleDto.Description);
        cmbRole.DataSource = roles.ToList();

        if (cmbRole.Items.Count > 0)
            cmbRole.SelectedIndex = 0;

        // --------------------------------------------------
        // Validation hooks
        // --------------------------------------------------

        txtUsername.TextChanged += ValidateInput;
        txtDisplayName.TextChanged += ValidateInput;
        txtEmail.TextChanged += ValidateInput;
        txtPassword.TextChanged += ValidateInput;
        txtConfirmPassword.TextChanged += ValidateInput;
        cmbRole.SelectedIndexChanged += ValidateInput;
    }

    // --------------------------------------------------
    // Validation
    // --------------------------------------------------

    private void ValidateInput(object? sender, EventArgs e)
    {
        btnSave.Enabled =
            !string.IsNullOrWhiteSpace(Username) &&
            !string.IsNullOrWhiteSpace(DisplayName) &&
            !string.IsNullOrWhiteSpace(Email) &&
            !string.IsNullOrWhiteSpace(RoleName) &&
            !string.IsNullOrWhiteSpace(Password) &&
            Password == txtConfirmPassword.Text;
    }

    // --------------------------------------------------
    // Actions
    // --------------------------------------------------

    private void btnSave_Click(object sender, EventArgs e)
    {
        DialogResult = DialogResult.OK;
        Close();
    }

    private void btnCancel_Click(object sender, EventArgs e)
    {
        Close();
    }

    private void btnClear_Click(object sender, EventArgs e)
    {
        txtUsername.Clear();
        txtDisplayName.Clear();
        txtEmail.Clear();
        txtPassword.Clear();
        txtConfirmPassword.Clear();

        if (cmbRole.Items.Count > 0)
            cmbRole.SelectedIndex = 0;

        btnSave.Enabled = false;
        txtUsername.Focus();
    }

    // --------------------------------------------------
    // Failure handling
    // --------------------------------------------------

    public void ResetAfterFailure(string message)
    {
        MessageBox.Show(
            message,
            "User creation failed",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning);

        txtPassword.Clear();
        txtConfirmPassword.Clear();
        btnSave.Enabled = false;
        txtUsername.Focus();
    }

    // --------------------------------------------------
    // Role refresh (safe retry support)
    // --------------------------------------------------

    public void RefreshRoles(IEnumerable<RoleDto> roles)
    {
        var currentRoleName = RoleName;

        cmbRole.DataSource = null;
        cmbRole.DisplayMember = nameof(RoleDto.RoleName);
        cmbRole.ValueMember = nameof(RoleDto.RoleName);
        cmbRole.DataSource = roles.ToList();

        if (cmbRole.Items.Count == 0)
            return;

        if (!string.IsNullOrWhiteSpace(currentRoleName))
        {
            cmbRole.SelectedValue = currentRoleName;

            if (cmbRole.SelectedIndex == -1)
                cmbRole.SelectedIndex = 0;
        }
        else
        {
            cmbRole.SelectedIndex = 0;
        }
    }
}
