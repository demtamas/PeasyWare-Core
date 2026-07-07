using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Infrastructure.Bootstrap;
using System;
using System.Linq;
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

        Text = $"PeasyWare – {session.DisplayName ?? session.Username} | Session {session.SessionId.ToString()[..8]}";

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
        _heartbeatTimer.Interval = 30000; // 30s — fast enough to catch expiry, not so frequent it blocks

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
        // Fast path — just check local flag.
        // The heartbeat timer (60s) handles the actual DB touch.
        // Hitting the DB on every button click blocks the UI thread.
        if (_sessionExpired || isSessionExpired)
            return false;

        return true;
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

        HookGlobalInteraction(view);

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

    private void clientSettingsToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateClientsView(_session));

    private void inventoryActiveToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateInventoryView(_session));
    }

    private void materialsToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateMaterialsView(_session));
    }

    private void skuChangesToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateSkuAuditView(_session));
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

            Cursor = Cursors.WaitCursor;
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
        finally
        {
            Cursor = Cursors.Default;
        }
    }

    // ==========================================================
    // Help menu
    // ==========================================================

    private void aboutPeasyWareToolStripMenuItem_Click(object sender, EventArgs e)
    {
        using var dlg = new PeasyWare.Desktop.Forms.Help.AboutForm();
        dlg.ShowDialog(this);
    }

    private void versionInfoToolStripMenuItem_Click(object sender, EventArgs e)
    {
        var cs     = _runtime.ConnectionFactory.ConnectionString;
        var server = ParseCsKey(cs, "Server", "Data Source") ?? "(unknown)";
        var db     = ParseCsKey(cs, "Database", "Initial Catalog") ?? "(unknown)";

        using var dlg = new PeasyWare.Desktop.Forms.Help.VersionInfoForm(
            _session, server, db);
        dlg.ShowDialog(this);
    }

    private void databaseVersionToolStripMenuItem_Click(object sender, EventArgs e)
    {
        var cs      = _runtime.ConnectionFactory.ConnectionString;
        var server  = ParseCsKey(cs, "Server", "Data Source") ?? "(unknown)";
        var db      = ParseCsKey(cs, "Database", "Initial Catalog") ?? "(unknown)";

        var settings    = _runtime.SettingsQueryRepository.GetSettings();
        var verSetting  = settings.FirstOrDefault(s => s.SettingName == "core.version");
        var schemaVer   = verSetting?.SettingValue ?? "(unknown)";
        var schemaUpdated = verSetting?.UpdatedAt;

        using var dlg = new PeasyWare.Desktop.Forms.Help.DatabaseVersionForm(
            schemaVer, server, db, schemaUpdated);
        dlg.ShowDialog(this);
    }

    private void supportToolStripMenuItem_Click(object sender, EventArgs e)
    {
        var asm       = System.Reflection.Assembly.GetEntryAssembly();
        var ver       = asm?.GetName().Version;
        var appVer    = ver is not null ? $"{ver.Major}.{ver.Minor}.{ver.Build}" : "1.0";

        var settings  = _runtime.SettingsQueryRepository.GetSettings();
        var schemaVer = settings.FirstOrDefault(s => s.SettingName == "core.version")?.SettingValue ?? "(unknown)";

        using var dlg = new PeasyWare.Desktop.Forms.Help.SupportForm(
            _session.SessionId.ToString(), appVer, schemaVer);
        dlg.ShowDialog(this);
    }

    /// <summary>Simple key-value parser for SQL Server connection strings.</summary>
    private static string? ParseCsKey(string cs, params string[] keys)
    {
        foreach (var pair in cs.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var idx = pair.IndexOf('=');
            if (idx < 0) continue;
            var key = pair[..idx].Trim();
            var val = pair[(idx + 1)..].Trim();
            foreach (var k in keys)
                if (key.Equals(k, StringComparison.OrdinalIgnoreCase))
                    return val;
        }
        return null;
    }

    private void movementsToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateMovementsView(_session));

    private void allEventsToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateEventLogView(_session));

    private void loginAttemptsToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateEventLogView(_session, actionFilter: "AuthService.Login"));

    private void userChangesToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateUserActivityView(_session));

    private void locationChangesToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateLocationAuditView(_session));

    private void inboundToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateInboundView(_session));
    }

    private void allPartiesToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreatePartiesView(_session));

    private void suppliersPartiesMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreatePartiesView(_session, "SUPPLIER"));

    private void customersPartiesMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreatePartiesView(_session, "CUSTOMER"));

    private void hauliersPartiesMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreatePartiesView(_session, "HAULIER"));

    private void ownersPartiesMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreatePartiesView(_session, "OWNER"));

    private void shipmentsToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateShipmentsView(_session));
    }

    private void warehouseTasksToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateTasksView(_session));
    }

    private void locationsToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateLocationsView(_session));

    private void zonesToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateZonesView(_session));

    private void sectionsToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateSectionsView(_session));

    private void storageTypesToolStripMenuItem_Click(object sender, EventArgs e)
        => ShowView(_views.CreateStorageTypesView(_session));

    private void outstandiToolStripMenuItem_Click(object sender, EventArgs e)
    {
        ShowView(_views.CreateOutstandingOrdersView(_session));
    }
}