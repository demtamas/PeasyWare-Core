using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Forms;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Infrastructure.Ui;
using System;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Sessions
{
    public partial class SessionsView : UserControl, IToolbarAware
    {
        private readonly Guid _currentSessionId;
        private readonly ISessionQueryRepository _repo;
        private readonly ISessionCommandRepository? _commandRepo;
        private readonly ISessionDetailsRepository _detailsRepo;

        private ToolStripButton? _btnRefresh;
        private ToolStripButton? _btnTerminate;
        private ToolStripButton? _btnDetails;

        public SessionsView(
            Guid currentSessionId,
            ISessionQueryRepository repo,
            ISessionCommandRepository? commandRepo,
            ISessionDetailsRepository detailsRepo)
        {
            InitializeComponent();

            _currentSessionId = currentSessionId;
            _repo = repo ?? throw new ArgumentNullException(nameof(repo));
            _commandRepo = commandRepo; // can be null if not wired yet
            _detailsRepo = detailsRepo ?? throw new ArgumentNullException(nameof(detailsRepo));

            // --------------------------------------------------
            // DataGridView – behaviour
            // --------------------------------------------------

            dgvSessions.AutoGenerateColumns = false;
            dgvSessions.ReadOnly = true;

            dgvSessions.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            dgvSessions.MultiSelect = false;

            dgvSessions.AllowUserToAddRows = false;
            dgvSessions.AllowUserToDeleteRows = false;
            dgvSessions.AllowUserToResizeRows = false;
            dgvSessions.RowHeadersVisible = false;

            dgvSessions.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

            // --------------------------------------------------
            // DataGridView – header styling (NO highlighting)
            // --------------------------------------------------

            dgvSessions.EnableHeadersVisualStyles = false;

            dgvSessions.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
            dgvSessions.ColumnHeadersDefaultCellStyle.ForeColor = SystemColors.ControlText;
            dgvSessions.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
            dgvSessions.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
            dgvSessions.ColumnHeadersDefaultCellStyle.Font =
                new Font(dgvSessions.Font, FontStyle.Bold);

            // --------------------------------------------------
            // Optional: calmer row selection (enterprise feel)
            // --------------------------------------------------

            dgvSessions.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
            dgvSessions.DefaultCellStyle.SelectionForeColor = Color.Black;

            // --------------------------------------------------
            // Columns + events
            // --------------------------------------------------

            ConfigureColumns(dgvSessions);

            dgvSessions.SelectionChanged += (_, _) => UpdateToolbarState();
            Load += (_, _) => LoadSessions();
        }

        // --------------------------------------------------
        // Toolbar integration
        // --------------------------------------------------

        public void ConfigureToolbar(ToolStrip toolStrip)
        {
            toolStrip.ImageScalingSize = new Size(16, 16);

            _btnRefresh = new ToolStripButton("Refresh")
            {
                Image = Icons.Refresh,
                DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
            };
            _btnRefresh.Click += (_, _) => LoadSessions();

            _btnTerminate = new ToolStripButton("Terminate")
            {
                Image = Icons.Terminate,
                Enabled = false,
                DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
            };
            _btnTerminate.Click += (_, _) => TerminateSelectedSession();

            _btnDetails = new ToolStripButton("Details")
            {
                Image = Icons.Details,
                Enabled = false,
                DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
            };
            _btnDetails.Click += (_, _) => ShowSessionDetails();

            toolStrip.Items.Add(_btnRefresh);
            toolStrip.Items.Add(new ToolStripSeparator());
            toolStrip.Items.Add(_btnTerminate);
            toolStrip.Items.Add(_btnDetails);

            UpdateToolbarState();
        }

        private void UpdateToolbarState()
        {
            if (_btnTerminate == null || _btnDetails == null)
                return;

            if (dgvSessions.SelectedRows.Count != 1)
            {
                _btnTerminate.Enabled = false;
                _btnDetails.Enabled = false;
                return;
            }

            var selected = dgvSessions.SelectedRows[0].DataBoundItem;
            if (selected == null)
            {
                _btnTerminate.Enabled = false;
                _btnDetails.Enabled = false;
                return;
            }

            // We don't want hard dependency on column names; use reflection-friendly approach:
            // Expect your DTO/model has a SessionId (Guid) property.
            var sessionIdProp = selected.GetType().GetProperty("SessionId");
            if (sessionIdProp == null || sessionIdProp.PropertyType != typeof(Guid))
            {
                _btnTerminate.Enabled = false;
                _btnDetails.Enabled = false;
                return;
            }

            var selectedSessionId = (Guid)sessionIdProp.GetValue(selected)!;
            var isOwnSession = selectedSessionId == _currentSessionId;

            _btnDetails.Enabled = true;

            // Can only terminate if repo exists AND it isn't your own session
            _btnTerminate.Enabled = (_commandRepo != null) && !isOwnSession;

            if (_commandRepo == null)
                _btnTerminate.ToolTipText = "Session commands are not available.";
            else if (isOwnSession)
                _btnTerminate.ToolTipText = "You cannot terminate your own session.";
            else
                _btnTerminate.ToolTipText = "Terminate selected session.";
        }

        // --------------------------------------------------
        // Grid
        // --------------------------------------------------

        private void ConfigureColumns(DataGridView dgv)
        {
            dgv.Columns["SessionId"]?.FillWeight = 25;
            dgv.Columns["Username"]?.FillWeight = 15;
            dgv.Columns["ClientApp"]?.FillWeight = 20;
            dgv.Columns["ClientInfo"]?.FillWeight = 15;
            dgv.Columns["LastSeen"]?.FillWeight = 15;
            dgv.Columns["IsActive"]?.FillWeight = 10;

            dgv.Columns["LastSeen"]?
                .DefaultCellStyle.Format = "dd/MM/yyyy HH:mm:ss";
        }

        private void LoadSessions()
        {
            var sessions = _repo
                .GetActiveSessions()
                .OrderByDescending(s => s.LastSeen)
                .ToList();

            dgvSessions.DataSource = sessions;
            dgvSessions.ClearSelection();
            UpdateToolbarState();
        }

        // --------------------------------------------------
        // Actions
        // --------------------------------------------------

        private void TerminateSelectedSession()
        {
            if (_commandRepo == null)
            {
                MessageBox.Show(
                    this,
                    "Session commands are not available.",
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            if (dgvSessions.SelectedRows.Count != 1)
            {
                MessageBox.Show(
                    this,
                    "Please select exactly one session to terminate.",
                    "No session selected",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return;
            }

            var selected = dgvSessions.SelectedRows[0].DataBoundItem;
            if (selected == null)
            {
                MessageBox.Show(
                    this,
                    "Unable to determine the selected session.",
                    "Invalid selection",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            var sessionIdProp = selected.GetType().GetProperty("SessionId");
            if (sessionIdProp == null || sessionIdProp.PropertyType != typeof(Guid))
            {
                MessageBox.Show(
                    this,
                    "Unable to determine the selected session.",
                    "Invalid selection",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            var sessionId = (Guid)sessionIdProp.GetValue(selected)!;

            if (sessionId == _currentSessionId)
            {
                MessageBox.Show(
                    this,
                    "You cannot terminate your own session.",
                    "Operation not allowed",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
                return;
            }

            var confirm = MessageBox.Show(
                this,
                "Terminate the selected session?\n\nThe user will be logged out immediately.",
                "Confirm termination",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);

            if (confirm != DialogResult.Yes)
                return;

            var result = _commandRepo.LogoutSession(
                sessionId,
                sourceApp: "PeasyWare.Desktop",
                sourceClient: Environment.MachineName,
                sourceIp: IpResolver.GetLocalIPv4() ?? "UNKNOWN");

            MessageBox.Show(
                this,
                result.FriendlyMessage ?? "Session terminated.",
                result.Success ? "Success" : "Failed",
                MessageBoxButtons.OK,
                result.Success ? MessageBoxIcon.Information : MessageBoxIcon.Error);

            LoadSessions();
        }

        private void ShowSessionDetails()
        {
            if (dgvSessions.SelectedRows.Count != 1)
                return;

            var selected = dgvSessions.SelectedRows[0].DataBoundItem;
            if (selected == null)
                return;

            var sessionIdProp = selected.GetType().GetProperty("SessionId");
            if (sessionIdProp == null || sessionIdProp.PropertyType != typeof(Guid))
                return;

            var sessionId = (Guid)sessionIdProp.GetValue(selected)!;

            var details = _detailsRepo.GetSessionDetails(sessionId);

            if (details == null)
            {
                MessageBox.Show(
                    this,
                    "Session details could not be loaded.",
                    "Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return;
            }

            using var dlg = new SessionDetailsForm(details);
            dlg.ShowDialog(this);
        }
    }
}
