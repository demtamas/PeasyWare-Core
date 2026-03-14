using PeasyWare.Application.Contexts;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Views.Sessions;
using PeasyWare.Desktop.Views.Users;
using PeasyWare.Infrastructure.Repositories;
using PeasyWare.Infrastructure.Sql;
using System;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms;

public partial class MainForm : Form
{
    private readonly SessionContext _session;

    private readonly ISessionQueryRepository _sessionQueryRepo;
    private readonly ISessionCommandRepository _commandRepo;
    private readonly ISessionDetailsRepository _sessionDetailsRepo;

    private readonly IUserQueryRepository _userQueryRepo;

    private bool _shutdownConfirmed;
    private bool _restartRequested;

    private readonly SqlConnectionFactory _connectionFactory;
    private readonly IErrorMessageResolver _messageResolver;
    private readonly ILogger _logger;

    public MainForm(
    SessionContext session,
    SqlConnectionFactory connectionFactory,
    IErrorMessageResolver messageResolver,
    ISessionQueryRepository sessionQueryRepo,
    ISessionCommandRepository sessionCommandRepo,
    ISessionDetailsRepository sessionDetailsRepo,
    IUserQueryRepository userQueryRepo,
    ILogger logger)   // ← add this
    {
        InitializeComponent();

        _session = session;
        _connectionFactory = connectionFactory;
        _messageResolver = messageResolver;

        _sessionQueryRepo = sessionQueryRepo;
        _commandRepo = sessionCommandRepo;
        _sessionDetailsRepo = sessionDetailsRepo;
        _userQueryRepo = userQueryRepo;

        _logger = logger;   // ← assign

        Text = $"PeasyWare – {session.Username} | Session {session.SessionId.ToString()[..8]}";
    }

    // --------------------------------------------------
    // View host
    // --------------------------------------------------

    private void ShowView(UserControl view)
    {
        pnlMain.SuspendLayout();
        pnlMain.Controls.Clear();

        view.Dock = DockStyle.Fill;
        pnlMain.Controls.Add(view);

        pnlMain.ResumeLayout();

        ConfigureToolbarFor(view);
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
        var sessionCommandRepo =
            new SqlSessionCommandRepository(
                _connectionFactory,
                _session.SessionId,
                _session.UserId,
                _messageResolver,
                _logger);

        var view = new SessionsView(
            _session.SessionId,
            _sessionQueryRepo,
            sessionCommandRepo,
            _sessionDetailsRepo);

        ShowView(view);
    }

    private void usersToolStripMenuItem_Click(object sender, EventArgs e)
    {
        var userCommandRepo =
            new SqlUserCommandRepository(
                _connectionFactory,
                _session.SessionId,
                _session.UserId,
                _messageResolver,
                _logger);

        var view = new UsersView(
            _session.SessionId,
            _userQueryRepo,
            userCommandRepo);

        ShowView(view);
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
        _restartRequested = true;

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
        _restartRequested = false;

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

        if (_shutdownConfirmed)
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
        _restartRequested = false;

        TryLogout();
    }

    // --------------------------------------------------
    // Logout (best-effort)
    // --------------------------------------------------

    private void TryLogout()
    {
        try
        {
            // Always use a session-bound repo instance for logout
            var sessionCommandRepo = new SqlSessionCommandRepository(
                _connectionFactory,
                _session.SessionId,
                _session.UserId,
                _messageResolver,
                _logger);

            var result = sessionCommandRepo.LogoutSession(
                _session.SessionId,
                sourceApp: "PeasyWare.Desktop",
                sourceClient: Environment.MachineName,
                sourceIp: IpResolver.GetLocalIPv4() ?? "UNKNOWN"
            );

            // If you want visibility during debugging:
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
            // Don’t swallow during debug—this is how bugs become ghosts.
            MessageBox.Show(
                ex.Message,
                "Logout exception",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

}
