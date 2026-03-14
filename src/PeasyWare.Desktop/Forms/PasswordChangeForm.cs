using System;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms
{
    public partial class PasswordChangeForm : Form
    {
        public string? NewPassword { get; private set; }
        private readonly bool _adminReset;

        public PasswordChangeForm(string username, bool adminReset = false)
        {
            InitializeComponent();

            _adminReset = adminReset;

            Text = "Change password";

            AcceptButton = btnOk;
            CancelButton = btnCancel;

            txtNewPassword.UseSystemPasswordChar = true;
            txtConfirmPassword.UseSystemPasswordChar = true;

            btnOk.Enabled = false;
            lblCapsLock.Visible = false;

            txtNewPassword.TextChanged += ValidateInput;
            txtConfirmPassword.TextChanged += ValidateInput;

            txtNewPassword.TextChanged += (_, _) =>
            {
                ValidateInput(null, EventArgs.Empty);
                UpdatePasswordHint();
            };

            txtNewPassword.KeyUp += (_, _) => UpdateCapsLockWarning();
            txtConfirmPassword.KeyUp += (_, _) => UpdateCapsLockWarning();

            // 🔹 tiny increment #1: sensible initial focus
            Shown += (_, _) => txtNewPassword.Focus();

            UpdateCapsLockWarning();
        }

        private void ValidateInput(object? sender, EventArgs e)
        {
            var p1 = txtNewPassword.Text;
            var p2 = txtConfirmPassword.Text;

            btnOk.Enabled =
                !string.IsNullOrWhiteSpace(p1) &&
                !string.IsNullOrWhiteSpace(p2) &&
                string.Equals(p1, p2, StringComparison.Ordinal);
        }

        private void UpdateCapsLockWarning()
        {
            lblCapsLock.Visible = Control.IsKeyLocked(Keys.CapsLock);
        }

        private void btnOk_Click(object sender, EventArgs e)
        {
            if (!btnOk.Enabled)
                return;

            NewPassword = txtNewPassword.Text;
            DialogResult = DialogResult.OK;
            Close();
        }

        private void btnCancel_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }

        // 🔹 tiny increment #2: caller can reset after backend rejection
        public void ResetInputs(string? message = null)
        {
            if (!string.IsNullOrWhiteSpace(message))
            {
                MessageBox.Show(
                    message,
                    "Password change",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }

            txtNewPassword.Clear();
            txtConfirmPassword.Clear();
            btnOk.Enabled = false;
            txtNewPassword.Focus();
        }
        private void UpdatePasswordHint()
        {
            var pwd = txtNewPassword.Text;

            if (string.IsNullOrWhiteSpace(pwd))
            {
                lblPasswordHint.Text = string.Empty;
                return;
            }

            if (pwd.Length < 8)
            {
                lblPasswordHint.Text = "Password is too short (min 8 characters).";
                return;
            }

            bool hasUpper = pwd.Any(char.IsUpper);
            bool hasLower = pwd.Any(char.IsLower);
            bool hasDigit = pwd.Any(char.IsDigit);
            bool hasSymbol = pwd.Any(c => !char.IsLetterOrDigit(c));

            int score =
                (hasUpper ? 1 : 0) +
                (hasLower ? 1 : 0) +
                (hasDigit ? 1 : 0) +
                (hasSymbol ? 1 : 0);

            lblPasswordHint.Text = score switch
            {
                <= 1 => "Weak password.",
                2 => "Okay, but could be stronger.",
                3 => "Strong password.",
                _ => "Very strong password."
            };
        }

    }
}
