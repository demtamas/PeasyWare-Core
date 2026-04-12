using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms;

public partial class MainForm : Form
{
    private readonly SessionContext _session;
    private readonly AppRuntime _runtime;
    private readonly ViewFactory _views;

    private bool _sessionExpired;
    private bool _shutdownConfirmed;

    private DateTime _lastUserInteraction = DateTime.UtcNow;
    private readonly TimeSpan _interactionGrace = TimeSpan.FromMinutes(2);

    private readonly System.Windows.Forms.Timer _heartbeatTimer = new();
    private bool isSessionExpired;

    // 🔥 NEW: UI state
    private string _currentViewName = "Home";

    public bool GetIsSessionExpired()
    {
        return isSessionExpired;
    }

    internal void SetIsSessionExpired(bool value)
    {
        isSessionExpired = value;
    }

    public MainForm(
        SessionContext session,
        AppRuntime runtime,
        ViewFactory views)
    {
        InitializeComponent();

        _session = session;
        _runtime = runtime;
        _views = views;

        Text = $"PeasyWare – {session.DisplayName} | Session {session.SessionId.ToString()[..8]}";

        HookGlobalInteraction(this);
        InitializeHeartbeat();

        UpdateStatusBar();
    }

    // --------------------------------------------------
    // Interaction tracking
    // --------------------------------------------------

    private void HookGlobalInteraction(Control parent)
    {
        parent.MouseDown += (_, _) => RegisterInteraction();
        parent.KeyDown += (_, _) => RegisterInteraction();

        foreach (Control child in parent.Controls)
        {
            HookGlobalInteraction(child);
        }
    }

    private void RegisterInteraction()
    {
        if (_sessionExpired)
            return;

        _lastUserInteraction = DateTime.UtcNow;

        UpdateStatusBar(); // 🔥 NEW
    }

    // --------------------------------------------------
    // Heartbeat (safe, no resurrection)
    // --------------------------------------------------

    private void InitializeHeartbeat()
    {
        _heartbeatTimer.Interval = 60000;

        _heartbeatTimer.Tick += (_, _) =>
        {
            if (_sessionExpired)
                return;

            try
            {
                var inactivity = DateTime.UtcNow - _lastUserInteraction;

                // Do NOT extend session if user inactive
                if (inactivity > _interactionGrace)
                {
                    UpdateStatusBar();
                    return;
                }

                var repo = _runtime.Repositories.CreateSessionCommand(_session);

                var result = repo.TouchSession(
                    _session.SessionId,
                    "PeasyWare.Desktop",
                    Environment.MachineName,
                    IpResolver.GetLocalIPv4());

                if (!result.IsAlive)
                {
                    HandleSessionExpired(
                        result.FriendlyMessage ?? "Session expired.");
                }

                UpdateStatusBar();
            }
            catch (SessionExpiredException ex)
            {
                HandleSessionExpired(ex.Message);
            }
        };

        _heartbeatTimer.Start();
    }

    // --------------------------------------------------
    // Status bar update
    // --------------------------------------------------

    private void UpdateStatusBar()
    {
        if (statusStrip1.Items.Count == 0)
            return;

        var inactivity = DateTime.UtcNow - _lastUserInteraction;

        var status =
            _sessionExpired
                ? "Expired"
                : inactivity > _interactionGrace
                    ? "Idle"
                    : "Active";

        // Correct expiry calculation
        var expiryTime = _lastUserInteraction.AddMinutes(_session.SessionTimeoutMinutes);
        var remaining = expiryTime - DateTime.UtcNow;

        var totalMinutes = Math.Max(0, (int)remaining.TotalMinutes);

        // Format as hours + minutes
        var hours = totalMinutes / 60;
        var minutes = totalMinutes % 60;

        string expiryText =
            hours > 0
                ? minutes > 0 ? $"{hours}h {minutes}m" : $"{hours}h"
                : $"{minutes} min";

        var text =
            $"User: {_session.Username} | " +
            $"Session: {_session.SessionId.ToString()[..8]} | " +
            $"View: {_currentViewName} | " +
            $"{status}";

        if (!_sessionExpired)
        {
            text += $" | Expires in: {expiryText}";
        }

        statusStrip1.Items[0].Text = text;
    }

    // --------------------------------------------------
    // Session validation (single source of truth)
    // --------------------------------------------------

    private bool EnsureSessionAlive()
    {
        Console.WriteLine($"TRACE.UI.Session: {_session.SessionId} / {_session.UserId}");

        if (_sessionExpired)
            return false;

        try
        {
            var repo = _runtime.Repositories.CreateSessionCommand(_session);

            var result = repo.TouchSession(
                _session.SessionId,
                "PeasyWare.Desktop",
                Environment.MachineName,
                IpResolver.GetLocalIPv4());

            if (!result.IsAlive)
            {
                HandleSessionExpired(
                    result.FriendlyMessage ?? "Session expired.");
                return false;
            }

            return true;
        }
        catch (SessionExpiredException ex)
        {
            HandleSessionExpired(ex.Message);
            return false;
        }
    }

    // --------------------------------------------------
    // View host
    // --------------------------------------------------

    private void ShowView(UserControl view)
    {
        if (!EnsureSessionAlive())
            return;

        pnlMain.SuspendLayout();
        pnlMain.Controls.Clear();

        view.Dock = DockStyle.Fill;
        pnlMain.Controls.Add(view);

        HookGlobalInteraction( view );

        pnlMain.ResumeLayout();

        ConfigureToolbarFor(view);

        // 🔥 NEW: track view name
        _currentViewName = view.GetType().Name.Replace("View", "");

        UpdateStatusBar(); // 🔥 NEW

        // Force UI refresh (fix toolbar hover issue)
        mainToolStrip.PerformLayout();
        mainToolStrip.Refresh();

        if (view is PeasyWare.Desktop.Views.Settings.SettingsView settingsView)
        {
            BeginInvoke(new Action(settingsView.ActivateView));
        }
    }

    // --------------------------------------------------
    // Toolbar adaptation
    // --------------------------------------------------

    private void ConfigureToolbarFor(Control view)
    {
        mainToolStrip.Items.Clear();

        if (view is IToolbarAware toolbarAware)
        {
            toolbarAware.ConfigureToolbar(mainToolStrip);
        }
    }

    // --------------------------------------------------
    // Menu actions
    // --------------------------------------------------

    private void sessionsToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateSessionsView(_session));
    }

    private void usersToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateUsersView(_session));
    }

    private void operationalSettingsToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateSettingsView(_session));
    }

    private void logoutToolStripMenuItem_Click(object sender, EventArgs e)
    {
        var confirm = MessageBox.Show(
            this,
            "Log out and return to the login screen?",
            "Logout",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes)
            return;

        _shutdownConfirmed = true;

        _heartbeatTimer.Stop();

        TryLogout();

        DialogResult = DialogResult.Abort;
        Close();
    }

    private void exitToolStripMenuItem_Click(object sender, EventArgs e)
    {
        var confirm = MessageBox.Show(
            this,
            "Exit PeasyWare?\n\nAny unsaved work may be lost.",
            "Exit application",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes)
            return;

        _shutdownConfirmed = true;

        _heartbeatTimer.Stop();

        TryLogout();

        DialogResult = DialogResult.OK;
        Close();
    }

    // --------------------------------------------------
    // Unified close handling
    // --------------------------------------------------

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        base.OnFormClosing(e);

        if (_shutdownConfirmed || _sessionExpired)
            return;

        var confirm = MessageBox.Show(
            this,
            "Exit PeasyWare?\n\nAny unsaved work may be lost.",
            "Exit application",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);

        if (confirm != DialogResult.Yes)
        {
            e.Cancel = true;
            return;
        }

        _shutdownConfirmed = true;

        _heartbeatTimer.Stop();

        TryLogout();
    }

    // --------------------------------------------------
    // Session expired handling
    // --------------------------------------------------

    public void HandleSessionExpired(string message)
    {
        if (_sessionExpired)
            return;

        _sessionExpired = true;
        _shutdownConfirmed = true;

        _heartbeatTimer.Stop();

        UpdateStatusBar(); // 🔥 NEW

        MessageBox.Show(
            this,
            message,
            "Session expired",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning);

        DialogResult = DialogResult.Abort;
        Close();
    }

    // --------------------------------------------------
    // Logout (best-effort)
    // --------------------------------------------------

    private void TryLogout()
    {
        try
        {
            var sessionCommandRepo =
                _runtime.Repositories.CreateSessionCommand(_session);

            var result = sessionCommandRepo.LogoutSession(
                _session.SessionId,
                sourceApp: "PeasyWare.Desktop",
                sourceClient: Environment.MachineName,
                sourceIp: IpResolver.GetLocalIPv4() ?? "UNKNOWN"
            );

            if (!result.Success)
            {
                MessageBox.Show(
                    result.FriendlyMessage ?? "Logout failed.",
                    "Logout",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                ex.Message,
                "Logout exception",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    public void ExecuteWithSession(Action action)
    {
        if (_sessionExpired)
            return;

        try
        {
            if (!EnsureSessionAlive())
                return;

            action();
        }
        catch (SessionExpiredException ex)
        {
            HandleSessionExpired(ex.Message);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                this,
                ex.Message,
                "Unexpected error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }
}