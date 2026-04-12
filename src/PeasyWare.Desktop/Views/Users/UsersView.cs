using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Desktop.Forms;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Infrastructure.Ui;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Users;

public partial class UsersView : BaseView, IToolbarAware
{
    private readonly Guid _currentSessionId;
    private readonly IUserQueryRepository _repo;
    private readonly IUserCommandRepository _commandRepo;
    private bool _onlineOnly = false;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnEnable;
    private ToolStripButton? _btnDisable;
    private ToolStripButton? _btnUnlock;
    private ToolStripButton? _btnOnlineFilter;
    private ToolStripButton? _btnLogoutAll;
    private ToolStripButton? _btnDetails;

    private TextBox? _txtSearch;
    private ToolStripControlHost? _searchHost;

    private ToolStripButton? _btnAdd;

    private List<UserSummaryDto> _users = new();

    private readonly ISessionCommandRepository _sessionRepo;

    public UsersView(
    Guid currentSessionId,
    IUserQueryRepository repo,
    IUserCommandRepository commandRepo,
    ISessionCommandRepository sessionRepo)
    {
        InitializeComponent();

        _currentSessionId = currentSessionId;
        _repo = repo;
        _commandRepo = commandRepo;
        _sessionRepo = sessionRepo;

        ConfigureGrid(dgvUsers);
        EnableDoubleBuffering(dgvUsers);

        dgvUsers.SelectionChanged += (_, _) => UpdateToolbarState();
        dgvUsers.CellFormatting += DgvUsers_CellFormatting;

        Load += (_, _) => LoadUsers();
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();
        toolStrip.ImageScalingSize = new Size(16, 16);

        _btnRefresh = new ToolStripButton("Refresh")
        {
            Image = Icons.Refresh,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnRefresh.Click += Wrap(RefreshUsers);

        _btnAdd = new ToolStripButton("Add")
        {
            //Image = Icons.Add,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnAdd.Click += Wrap(AddNewUser);

        _btnEnable = new ToolStripButton("Enable")
        {
            //Image = Icons.Enable,
            Enabled = false,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnEnable.Click += Wrap(EnableSelectedUser);

        _btnDisable = new ToolStripButton("Disable")
        {
            //Image = Icons.Disable,
            Enabled = false,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnDisable.Click += Wrap(DisableSelectedUser);

        _btnLogoutAll = new ToolStripButton("Logout All")
        {
            Image = Icons.Terminate, // reuse terminate icon
            Enabled = false,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnLogoutAll.Click += Wrap(LogoutSelectedUserEverywhere);

        _btnUnlock = new ToolStripButton("Unlock / Reset")
        {
            //Image = Icons.Unlock,
            Enabled = true,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnUnlock.Click += Wrap(UnlockSelectedUser);

        _btnDetails = new ToolStripButton("Details")
        {
            Image = Icons.Details,
            Enabled = false,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnDetails.Click += Wrap(ShowUserDetails);

        // 🔹 Online-only toggle (NO session needed)
        _btnOnlineFilter = new ToolStripButton("Online only")
        {
            CheckOnClick = true
        };
        _btnOnlineFilter.CheckedChanged += (_, _) =>
        {
            _onlineOnly = _btnOnlineFilter.Checked;
            _btnOnlineFilter.Text = _onlineOnly ? "Show all" : "Online only";
            ApplyClientSideFilter();
        };

        // 🔹 Search (NO session needed)
        _txtSearch = new TextBox { Width = 220 };
        _txtSearch.PlaceholderText = "Search username / display name…";
        _txtSearch.TextChanged += (_, _) => ApplyClientSideFilter();

        _searchHost = new ToolStripControlHost(_txtSearch)
        {
            AutoSize = false,
            Width = 240
        };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());

        toolStrip.Items.Add(_btnAdd);
        toolStrip.Items.Add(new ToolStripSeparator());

        toolStrip.Items.Add(_btnEnable);
        toolStrip.Items.Add(_btnDisable);
        toolStrip.Items.Add(_btnLogoutAll);
        toolStrip.Items.Add(_btnUnlock);
        toolStrip.Items.Add(new ToolStripSeparator());

        toolStrip.Items.Add(_btnDetails);
        toolStrip.Items.Add(new ToolStripSeparator());

        toolStrip.Items.Add(_btnOnlineFilter);
        toolStrip.Items.Add(new ToolStripSeparator());

        toolStrip.Items.Add(_searchHost);
    }

    private void RefreshUsers()
    {
        if (FindForm() is not MainForm main)
            return;

        main.ExecuteWithSession(() =>
        {
            LoadUsers();
        });
    }

    private void UpdateToolbarState()
    {
        if (_btnEnable == null || _btnDisable == null ||
            _btnUnlock == null || _btnLogoutAll == null || _btnDetails == null)
            return;

        if (GetSelectedUser() is not UserSummaryDto user)
        {
            _btnEnable.Enabled = false;
            _btnDisable.Enabled = false;
            _btnUnlock.Enabled = false;
            _btnLogoutAll.Enabled = false;
            _btnDetails.Enabled = false;
            return;
        }

        _btnEnable.Enabled = !user.IsActive;
        _btnDisable.Enabled = user.IsActive;
        _btnLogoutAll.Enabled = user.IsOnline;
        _btnUnlock.Enabled = true;
        _btnDetails.Enabled = true;
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadUsers()
    {
        _users = _repo.GetUsers(null).ToList();
        Bind(_users);
        ApplyClientSideFilter();
        UpdateToolbarState();
    }

    private void ApplyClientSideFilter()
    {
        if (_txtSearch is null)
            return;

        IEnumerable<UserSummaryDto> data = _users;

        // 🔹 Online-only filter
        if (_onlineOnly)
        {
            data = data.Where(u => u.IsOnline);
        }

        // 🔹 Text search filter
        var q = _txtSearch.Text.Trim();
        if (!string.IsNullOrWhiteSpace(q))
        {
            data = data.Where(u =>
                u.Username.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                u.DisplayName.Contains(q, StringComparison.OrdinalIgnoreCase));
        }

        Bind(data.ToList());
        UpdateToolbarState();
    }

    private void Bind(List<UserSummaryDto> data)
    {
        dgvUsers.DataSource = null;
        dgvUsers.DataSource = data;
    }

    private UserSummaryDto? GetSelectedUser()
        => dgvUsers.CurrentRow?.DataBoundItem as UserSummaryDto;

    // ==========================================================
    // Actions (THE MISSING METHODS)
    // ==========================================================

    private void EnableSelectedUser()
    {
        var user = GetSelectedUser();
        if (user is null) return;

        if (MessageBox.Show(
            this,
            $"Enable user '{user.Username}'?",
            "Enable user",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            return;

        _commandRepo.EnableUser(user.UserId);
        LoadUsers();
    }

    private void DisableSelectedUser()
    {
        var user = GetSelectedUser();
        if (user is null) return;

        if (MessageBox.Show(
            this,
            $"Disable user '{user.Username}'?\n\nThis will prevent new logins.",
            "Disable user",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            return;

        _commandRepo.DisableUser(user.UserId);
        LoadUsers();
    }

    private void LogoutSelectedUserEverywhere()
    {
        var user = GetSelectedUser();
        if (user is null) return;

        if (MessageBox.Show(
            this,
            $"Log out '{user.Username}' from ALL sessions?",
            "Logout user",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            return;

        _commandRepo.LogoutUserEverywhere(
            user.UserId,
            sourceApp: "PeasyWare.Desktop",
            sourceClient: Environment.MachineName,
            sourceIp: IpResolver.GetLocalIPv4());

        LoadUsers();
    }

    private void ShowUserDetails()
    {
        var user = GetSelectedUser();
        if (user is null) return;

        MessageBox.Show(
            this,
            $"User: {user.Username}\n" +
            $"Display: {user.DisplayName}\n" +
            $"Email: {user.Email}\n" +
            $"Role: {user.RoleName}\n" +
            $"Active: {user.IsActive}\n" +
            $"Online: {user.IsOnline}\n" +
            $"Failed Attempts: {user.FailedAttempts}",
            "User details",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns = false;
        dgv.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect = false;
        dgv.ReadOnly = true;

        dgv.AllowUserToAddRows = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;

        dgv.RowHeadersVisible = false;
        dgv.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        dgv.EnableHeadersVisualStyles = false;

        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font =
            new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Clear();

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.UserId),
            HeaderText = "ID",
            FillWeight = 6
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.Username),
            HeaderText = "Username",
            FillWeight = 16
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.DisplayName),
            HeaderText = "Display Name",
            FillWeight = 22
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.Email),
            HeaderText = "Email",
            FillWeight = 22
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.RoleName),
            HeaderText = "Role",
            FillWeight = 12
        });

        dgv.Columns.Add(new DataGridViewCheckBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.IsActive),
            HeaderText = "Active",
            FillWeight = 6
        });

        dgv.Columns.Add(new DataGridViewCheckBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.IsOnline),
            HeaderText = "Online",
            FillWeight = 6
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.LastLastSeen),
            HeaderText = "Last Seen",
            FillWeight = 16,
            DefaultCellStyle = new DataGridViewCellStyle
            {
                Format = "yyyy-MM-dd HH:mm:ss"
            }
        });

        dgv.Columns.Add(new DataGridViewCheckBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.IsLockedOut),
            HeaderText = "Locked",
            FillWeight = 6
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(UserSummaryDto.LockoutUntil),
            HeaderText = "Lockout Until",
            FillWeight = 16,
            DefaultCellStyle = new DataGridViewCellStyle { Format = "yyyy-MM-dd HH:mm:ss" }
        });

        dgv.Columns.OfType<DataGridViewCheckBoxColumn>()
            .ToList()
            .ForEach(c => c.DefaultCellStyle.Alignment = DataGridViewContentAlignment.MiddleCenter);

    }
    private static void EnableDoubleBuffering(DataGridView dgv)
    {
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
    }

    private void DgvUsers_CellFormatting(object? sender, DataGridViewCellFormattingEventArgs e)
    {
        if (dgvUsers.Rows[e.RowIndex].DataBoundItem is not UserSummaryDto user)
            return;

        var row = dgvUsers.Rows[e.RowIndex];

        if (user.IsLockedOut)
        {
            row.DefaultCellStyle.BackColor = Color.MistyRose;
        }
        else if (user.IsOnline)
        {
            row.DefaultCellStyle.BackColor = Color.FromArgb(230, 245, 230);
        }
        else
        {
            row.DefaultCellStyle.BackColor = Color.White;
        }
    }

    private void AddNewUser()
    {
        var roles = _repo.GetRoles();

        while (true)
        {
            using var dlg = new AddUserForm(roles);

            if (dlg.ShowDialog(this) != DialogResult.OK)
                return;

            var result = _commandRepo.CreateUser(
                dlg.Username,
                dlg.DisplayName,
                dlg.RoleName,
                dlg.Email,
                dlg.Password
            );

            if (result.Success)
            {
                LoadUsers();
                return;
            }

            MessageBox.Show(
                result.FriendlyMessage ?? "User could not be created.",
                "User creation failed",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);

            // loop continues → brand new dialog
        }
    }
    private void UnlockSelectedUser()
    {
        var user = GetSelectedUser();
        if (user is null)
            return;

        if (MessageBox.Show(
            this,
            $"Reset password for '{user.Username}'?\n\n" +
            "The user will be forced to choose a new password at next login.",
            "Reset password",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                    return;

        using var dlg = new PasswordChangeForm(user.Username);

        if (dlg.ShowDialog(this) != DialogResult.OK)
            return;

        var newPwd = dlg.NewPassword;
        if (string.IsNullOrWhiteSpace(newPwd))
            return;

        var result = _commandRepo.ResetPasswordAsAdmin(user.UserId, newPwd);

        if (!result.Success)
        {
            MessageBox.Show(
                result.FriendlyMessage ?? "Password reset failed.",
                "Unlock / Reset",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);

            return;
        }

        LoadUsers();
    }
}
