using PeasyWare.Application;
using PeasyWare.Application.Flows;

namespace PeasyWare.Desktop.Forms;

public partial class LoginForm : Form
{
    private readonly LoginFlow _loginFlow;
    private readonly bool _diagnosticsEnabled;

    public Guid? SessionId { get; private set; }
    public int? UserId { get; private set; }
    public string Username { get; private set; } = "";
    public string DisplayName { get; private set; } = "";
    public string? RoleName { get; private set; }
    public UiMode UiMode { get; private set; } = UiMode.Minimal;
    public int SessionTimeoutMinutes { get; private set; }

    public LoginForm(LoginFlow loginFlow, bool diagnosticsEnabled)
    {
        InitializeComponent();

        btnLogin.Enabled = false;
        _loginFlow = loginFlow;
        _diagnosticsEnabled = diagnosticsEnabled;

        CancelButton = btnExit;

        txtPassword.Enter += (_, _) => UpdateCapsLockWarning();
        txtPassword.Leave += (_, _) => lblCapsLock.Visible = false;
        txtPassword.KeyUp += (_, _) => UpdateCapsLockWarning();
    }

    private void btnLogin_Click(object sender, EventArgs e)
    {
        var username = txtUsername.Text.Trim();
        var password = txtPassword.Text;

        if (string.IsNullOrWhiteSpace(username) ||
            string.IsNullOrWhiteSpace(password))
        {
            MessageBox.Show(
                "Please enter username and password.",
                "Login",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        var context = BuildBaseContext(forceLogin: false);

        var result = _loginFlow.Run(
            username,
            password,
            context,
            _diagnosticsEnabled);

        switch (result.Outcome)
        {
            case LoginOutcome.Success:
                SessionId = result.SessionId;
                UserId = result.UserId;
                Username = username;
                DisplayName = result.DisplayName ?? username;
                RoleName = result.RoleName;
                UiMode = result.UiMode;
                SessionTimeoutMinutes = result.SessionTimeoutMinutes;
                DialogResult = DialogResult.OK;
                Close();
                return;

            case LoginOutcome.PasswordChangeRequired:
                HandlePasswordChange(username, password);
                return;

            case LoginOutcome.AlreadyLoggedIn:
                HandleAlreadyLoggedIn(username, password);
                return;

            default:
                MessageBox.Show(
                    result.Message ?? "Login failed.",
                    "Login failed",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                txtPassword.Clear();
                txtPassword.Focus();
                return;
        }
    }

    private static LoginContext BuildBaseContext(bool forceLogin)
        => new LoginContext
        {
            ClientApp = "PeasyWare.Desktop",
            ClientInfo = Environment.MachineName,
            OsInfo = Environment.OSVersion.ToString(),
            IpAddress = IpResolver.GetLocalIPv4() ?? "UNKNOWN",
            ForceLogin = forceLogin,
            CorrelationId = Guid.NewGuid()
        };

    private void HandlePasswordChange(string username, string oldPassword)
    {
        using var pwdForm = new PasswordChangeForm(username);

        if (pwdForm.ShowDialog() != DialogResult.OK ||
            string.IsNullOrWhiteSpace(pwdForm.NewPassword))
        {
            MessageBox.Show(
                "Password change was cancelled.",
                "Login",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            txtPassword.Clear();
            txtPassword.Focus();
            return;
        }

        var changeResult = _loginFlow.ChangePassword(username, pwdForm.NewPassword);

        if (!changeResult.Success)
        {
            MessageBox.Show(
                changeResult.FriendlyMessage ?? "Password change failed.",
                "Password change failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            txtPassword.Clear();
            txtPassword.Focus();
            return;
        }

        var retryContext = BuildBaseContext(forceLogin: false);

        var retryResult = _loginFlow.Run(
            username,
            pwdForm.NewPassword,
            retryContext,
            _diagnosticsEnabled);

        if (!retryResult.Success)
        {
            MessageBox.Show(
                retryResult.Message ?? "Login failed after password change.",
                "Login failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            txtPassword.Clear();
            txtPassword.Focus();
            return;
        }

        SessionId = retryResult.SessionId;
        UserId = retryResult.UserId;
        RoleName = retryResult.RoleName;
        UiMode = retryResult.UiMode;
        DialogResult = DialogResult.OK;
        Close();
    }

    private void HandleAlreadyLoggedIn(string username, string password)
    {
        var confirm = MessageBox.Show(
            "You are already logged in from this application.\n\n" +
            "Do you want to terminate the other session and continue?",
            "Active session detected",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes)
        {
            txtPassword.Clear();
            txtPassword.Focus();
            return;
        }

        var forcedContext = BuildBaseContext(forceLogin: true);

        var retryResult = _loginFlow.Run(
            username,
            password,
            forcedContext,
            _diagnosticsEnabled);

        if (!retryResult.Success)
        {
            MessageBox.Show(
                retryResult.Message ?? "Login failed.",
                "Login failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            txtPassword.Clear();
            txtPassword.Focus();
            return;
        }

        SessionId = retryResult.SessionId;
        UserId = retryResult.UserId;
        RoleName = retryResult.RoleName;
        UiMode = retryResult.UiMode;
        DialogResult = DialogResult.OK;
        Close();
    }

    private void btnClear_Click(object sender, EventArgs e)
    {
        txtUsername.Clear();
        txtPassword.Clear();
        btnLogin.Enabled = false;
        txtUsername.Focus();
    }

    private void btnExit_Click(object sender, EventArgs e)
    {
        DialogResult = DialogResult.Cancel;
        Close();
    }

    private void Credentials_TextChanged(object? sender, EventArgs e)
    {
        var canLogin =
            !string.IsNullOrWhiteSpace(txtUsername.Text) &&
            !string.IsNullOrWhiteSpace(txtPassword.Text);

        btnLogin.Enabled = canLogin;
        AcceptButton = canLogin ? btnLogin : null;
    }

    private void UpdateCapsLockWarning()
    {
        lblCapsLock.Visible = Control.IsKeyLocked(Keys.CapsLock);
    }
}