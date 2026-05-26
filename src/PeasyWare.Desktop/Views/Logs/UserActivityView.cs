using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Logs;

public sealed class UserActivityView : BaseView, IToolbarAware
{
    private readonly IEventLogQueryRepository _queryRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _fromDateHost;
    private ToolStripControlHost? _toDateHost;
    private TextBox?              _txtSearch;
    private DateTimePicker?       _dtpFrom;
    private DateTimePicker?       _dtpTo;

    private List<UserActivityDto> _events = [];

    public UserActivityView(IEventLogQueryRepository queryRepo)
    {
        _queryRepo = queryRepo;

        dgvActivity = new DataGridView { Dock = DockStyle.Fill };
        ConfigureGrid(dgvActivity);
        EnableDoubleBuffering(dgvActivity);
        Controls.Add(dgvActivity);

        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Size                = new Size(1200, 686);

        Load += (_, _) => Execute(LoadEvents);
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadEvents);

        _txtSearch = new TextBox { PlaceholderText = "Search user / event / detail...", Width = 220 };
        _txtSearch.TextChanged += (_, _) => ApplyFilter();
        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 240 };

        _dtpFrom = new DateTimePicker { Format = DateTimePickerFormat.Short, Value = DateTime.Today.AddDays(-7), Width = 90 };
        _dtpFrom.ValueChanged += (_, _) => Execute(LoadEvents);
        _fromDateHost = new ToolStripControlHost(_dtpFrom) { AutoSize = false, Width = 95 };

        _dtpTo = new DateTimePicker { Format = DateTimePickerFormat.Short, Value = DateTime.Today, Width = 90 };
        _dtpTo.ValueChanged += (_, _) => Execute(LoadEvents);
        _toDateHost = new ToolStripControlHost(_dtpTo) { AutoSize = false, Width = 95 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(new ToolStripLabel("From:"));
        toolStrip.Items.Add(_fromDateHost);
        toolStrip.Items.Add(new ToolStripLabel("To:"));
        toolStrip.Items.Add(_toDateHost);
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns   = false;
        dgv.SelectionMode         = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect           = false;
        dgv.ReadOnly              = true;
        dgv.AllowUserToAddRows    = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;
        dgv.RowHeadersVisible     = false;
        dgv.AutoSizeColumnsMode   = DataGridViewAutoSizeColumnsMode.Fill;
        dgv.BackgroundColor       = SystemColors.Window;

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Clear();
        dgv.Columns.Add(Col(nameof(UserActivityDto.OccurredAt),      "Time",          10));
        dgv.Columns.Add(Col(nameof(UserActivityDto.Source),          "Source",         5));
        dgv.Columns.Add(Col(nameof(UserActivityDto.EventType),       "Event",         18));
        dgv.Columns.Add(Col(nameof(UserActivityDto.SubjectUsername), "Subject",        8));
        dgv.Columns.Add(Col(nameof(UserActivityDto.ActorUsername),   "By",             8));
        dgv.Columns.Add(Col(nameof(UserActivityDto.Detail),          "Detail",        20));
        dgv.Columns.Add(Col(nameof(UserActivityDto.ResultCode),      "Result",         8));
        dgv.Columns.Add(Col(nameof(UserActivityDto.SourceApp),       "App",            8));

        // Colour by event type
        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(UserActivityDto.EventType)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "user.created"                      => Color.DarkGreen,
                "user.password.changed"             => Color.DarkBlue,
                "SET_ACTIVE"                        => Color.DarkOrange,
                "TERMINAL_LOCK"                     => Color.DarkRed,
                "FAILED_LOGIN_ATTEMPT"              => Color.Crimson,
                "AuthService.Login.Result"          => Color.Teal,
                "Session.Start"                     => Color.SeaGreen,
                "Session.Logout"                    => Color.Gray,
                _                                   => Color.Black
            };
        };

        // Row tint for security events
        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not UserActivityDto evt) return;

            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = evt.EventType switch
            {
                "TERMINAL_LOCK"        => Color.FromArgb(255, 235, 235),
                "FAILED_LOGIN_ATTEMPT" => Color.FromArgb(255, 245, 240),
                _                      => SystemColors.Window
            };
        };
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill };

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadEvents()
    {
        _events = _queryRepo.GetUserActivity(
            fromDate: _dtpFrom?.Value.Date,
            toDate:   _dtpTo?.Value.Date
        ).ToList();

        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _events
            : _events.Where(e =>
                e.EventType.Contains(q, StringComparison.OrdinalIgnoreCase)                  ||
                (e.SubjectUsername ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)    ||
                (e.ActorUsername   ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)    ||
                (e.Detail          ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)    ||
                (e.ResultCode      ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        dgvActivity.DataSource = null;
        dgvActivity.DataSource = data;
    }

    private readonly DataGridView dgvActivity;
}
