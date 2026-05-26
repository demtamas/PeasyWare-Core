using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text.Json;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Logs;

public sealed class EventLogView : BaseView, IToolbarAware
{
    private readonly IEventLogQueryRepository _queryRepo;

    private ToolStripButton?      _btnRefresh;
    private ToolStripButton?      _btnCopyPayload;
    private ToolStripControlHost? _searchHost;
    private ToolStripControlHost? _levelHost;
    private ToolStripControlHost? _fromDateHost;
    private ToolStripControlHost? _toDateHost;
    private TextBox?              _txtSearch;
    private ComboBox?             _cmbLevel;
    private DateTimePicker?       _dtpFrom;
    private DateTimePicker?       _dtpTo;

    private List<EventLogDto> _events = [];
    private string? _correlationFilter = null;
    private string? _pendingActionFilter = null;

    // Row background colours for WARN / ERROR
    private static readonly Color _warnBack  = Color.FromArgb(255, 248, 225);   // pale amber
    private static readonly Color _errorBack = Color.FromArgb(255, 235, 235);   // pale red
    private static readonly Color _warnFore  = Color.FromArgb(130, 80, 0);
    private static readonly Color _errorFore = Color.FromArgb(160, 0, 0);

    public EventLogView(IEventLogQueryRepository queryRepo)
    {
        InitializeComponent();

        _queryRepo = queryRepo;

        ConfigureGrid(dgvEvents);
        EnableDoubleBuffering(dgvEvents);

        dgvEvents.SelectionChanged += (_, _) => OnEventSelected();

        Load += (_, _) => Execute(LoadEvents);
    }

    public void SetActionFilter(string filter)
    {
        _pendingActionFilter = filter;
        // If toolbar already wired, apply immediately
        if (_txtSearch is not null)
            _txtSearch.Text = filter;
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadEvents);

        _btnCopyPayload = new ToolStripButton("Copy payload")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnCopyPayload.Click += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(txtPayload.Text))
                Clipboard.SetText(txtPayload.Text);
        };

        _txtSearch = new TextBox { PlaceholderText = "Search action / user / result / correlation...", Width = 260 };
        _txtSearch.TextChanged += (_, _) =>
        {
            _correlationFilter = null;   // clear corr filter when typing
            ApplyFilter();
        };
        _searchHost = new ToolStripControlHost(_txtSearch) { AutoSize = false, Width = 280 };

        _cmbLevel = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 80 };
        _cmbLevel.Items.AddRange(["All", "INFO", "WARN", "ERROR"]);
        _cmbLevel.SelectedIndex = 0;
        _cmbLevel.SelectedIndexChanged += (_, _) => Execute(LoadEvents);
        _levelHost = new ToolStripControlHost(_cmbLevel) { AutoSize = false, Width = 95 };

        _dtpFrom = new DateTimePicker { Format = DateTimePickerFormat.Short, Value = DateTime.Today.AddDays(-1), Width = 90 };
        _dtpFrom.ValueChanged += (_, _) => Execute(LoadEvents);
        _fromDateHost = new ToolStripControlHost(_dtpFrom) { AutoSize = false, Width = 95 };

        _dtpTo = new DateTimePicker { Format = DateTimePickerFormat.Short, Value = DateTime.Today, Width = 90 };
        _dtpTo.ValueChanged += (_, _) => Execute(LoadEvents);
        _toDateHost = new ToolStripControlHost(_dtpTo) { AutoSize = false, Width = 95 };

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnCopyPayload);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_searchHost);
        toolStrip.Items.Add(_levelHost);
        toolStrip.Items.Add(new ToolStripLabel("From:"));
        toolStrip.Items.Add(_fromDateHost);
        toolStrip.Items.Add(new ToolStripLabel("To:"));
        toolStrip.Items.Add(_toDateHost);

        // Apply any pre-set filter now that _txtSearch exists
        if (_pendingActionFilter is not null)
            _txtSearch.Text = _pendingActionFilter;
    }

    // ==========================================================
    // Layout — split pane: grid top, JSON detail bottom
    // ==========================================================

    private void InitializeComponent()
    {
        var split = new SplitContainer
        {
            Dock             = DockStyle.Fill,
            Orientation      = Orientation.Horizontal,
            SplitterDistance = 420
        };

        dgvEvents = new DataGridView { Dock = DockStyle.Fill };

        txtPayload = new RichTextBox
        {
            Dock        = DockStyle.Fill,
            ReadOnly    = true,
            Font        = new Font("Consolas", 9f),
            BackColor   = Color.FromArgb(30, 30, 30),
            ForeColor   = Color.LightGreen,
            BorderStyle = BorderStyle.None,
            ScrollBars  = RichTextBoxScrollBars.Both,
            WordWrap    = false
        };

        // Payload header bar with label + correlation ID link
        var pnlPayloadHeader = new Panel
        {
            Dock      = DockStyle.Top,
            Height    = 24,
            BackColor = SystemColors.ControlLight
        };

        var lblPayload = new Label
        {
            Text      = "Payload",
            Location  = new Point(4, 4),
            AutoSize  = true,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f, FontStyle.Bold)
        };

        _lblCorrelation = new LinkLabel
        {
            Text      = "",
            Location  = new Point(100, 4),
            AutoSize  = true,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8f),
            Visible   = false
        };
        _lblCorrelation.LinkClicked += (_, _) => FilterByCorrelation();

        pnlPayloadHeader.Controls.Add(lblPayload);
        pnlPayloadHeader.Controls.Add(_lblCorrelation);

        split.Panel1.Controls.Add(dgvEvents);
        split.Panel2.Controls.Add(txtPayload);
        split.Panel2.Controls.Add(pnlPayloadHeader);

        Controls.Add(split);
        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode       = AutoScaleMode.Font;
        Size                = new Size(1200, 686);
    }

    // ==========================================================
    // Grid config
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
        dgv.Columns.Add(Col(nameof(EventLogDto.OccurredAt),   "Time",          10));
        dgv.Columns.Add(Col(nameof(EventLogDto.Level),        "Level",          4));
        dgv.Columns.Add(Col(nameof(EventLogDto.Action),       "Action",        18));
        dgv.Columns.Add(Col(nameof(EventLogDto.Username),     "User",           6));
        dgv.Columns.Add(Col(nameof(EventLogDto.SourceApp),    "App",            8));
        dgv.Columns.Add(Col(nameof(EventLogDto.SourceClient), "Client",         8));
        dgv.Columns.Add(Col(nameof(EventLogDto.ResultCode),   "Result",         8));

        // Row-level colour: WARN = amber tint, ERROR = red tint
        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not EventLogDto evt) return;

            var (back, fore) = evt.Level switch
            {
                "ERROR" => (_errorBack, _errorFore),
                "WARN"  => (_warnBack,  _warnFore),
                _       => (SystemColors.Window, SystemColors.ControlText)
            };

            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = back;
            dgv.Rows[e.RowIndex].DefaultCellStyle.ForeColor = fore;
        };

        // Level cell: bold + appropriate colour
        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(EventLogDto.Level)) return;

            (e.CellStyle.ForeColor, e.CellStyle.Font) = e.Value?.ToString() switch
            {
                "ERROR" => (Color.DarkRed,    new Font(dgv.Font, FontStyle.Bold)),
                "WARN"  => (Color.DarkOrange, new Font(dgv.Font, FontStyle.Bold)),
                "INFO"  => (Color.DarkGreen,  dgv.Font),
                _       => (Color.Black,       dgv.Font)
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
        var level = _cmbLevel?.SelectedIndex is > 0
            ? _cmbLevel.SelectedItem?.ToString()
            : null;

        _events = _queryRepo.GetEventLog(
            levelFilter: level,
            fromDate:    _dtpFrom?.Value.Date,
            toDate:      _dtpTo?.Value.Date
        ).ToList();

        _correlationFilter = null;
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        // Correlation filter takes priority when set
        if (_correlationFilter is not null)
        {
            var corrId = _correlationFilter;
            var corrData = _events.Where(e =>
                e.PayloadJson?.Contains(corrId, StringComparison.OrdinalIgnoreCase) == true
            ).ToList();
            dgvEvents.DataSource = null;
            dgvEvents.DataSource = corrData;
            txtPayload.Clear();
            if (_btnCopyPayload is not null) _btnCopyPayload.Enabled = false;
            return;
        }

        var q = _txtSearch?.Text.Trim() ?? "";
        var data = string.IsNullOrWhiteSpace(q)
            ? _events
            : _events.Where(e =>
                e.Action.Contains(q, StringComparison.OrdinalIgnoreCase)                ||
                (e.Username     ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)  ||
                (e.ResultCode   ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)  ||
                (e.SourceApp    ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)  ||
                (e.SourceClient ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)  ||
                (e.PayloadJson  ?? "").Contains(q, StringComparison.OrdinalIgnoreCase)
            ).ToList();

        dgvEvents.DataSource = null;
        dgvEvents.DataSource = data;
        txtPayload.Clear();
        if (_btnCopyPayload is not null) _btnCopyPayload.Enabled = false;
    }

    private void OnEventSelected()
    {
        if (dgvEvents.SelectedRows.Count == 0) return;
        if (dgvEvents.SelectedRows[0].DataBoundItem is not EventLogDto evt) return;

        if (string.IsNullOrWhiteSpace(evt.PayloadJson))
        {
            txtPayload.Text = "(no payload)";
            if (_btnCopyPayload is not null) _btnCopyPayload.Enabled = false;
            if (_lblCorrelation is not null) _lblCorrelation.Visible = false;
            return;
        }

        try
        {
            var doc    = JsonDocument.Parse(evt.PayloadJson);
            var pretty = JsonSerializer.Serialize(doc, new JsonSerializerOptions { WriteIndented = true });
            txtPayload.Text = pretty;
        }
        catch
        {
            txtPayload.Text = evt.PayloadJson;
        }

        if (_btnCopyPayload is not null) _btnCopyPayload.Enabled = true;

        // Show correlation ID link if present
        if (_lblCorrelation is not null)
        {
            if (evt.PayloadJson is not null)
            {
                try
                {
                    var doc = JsonDocument.Parse(evt.PayloadJson);
                    if (doc.RootElement.TryGetProperty("Session", out var session) &&
                        session.TryGetProperty("CorrelationId", out var corrId))
                    {
                        var id = corrId.GetString();
                        if (!string.IsNullOrEmpty(id))
                        {
                            _lblCorrelation.Text    = $"Correlation: {id[..8]}…  (click to filter)";
                            _lblCorrelation.Tag     = id;
                            _lblCorrelation.Visible = true;
                        }
                        else
                        {
                            _lblCorrelation.Visible = false;
                        }
                    }
                    else
                    {
                        _lblCorrelation.Visible = false;
                    }
                }
                catch
                {
                    _lblCorrelation.Visible = false;
                }
            }
            else
            {
                _lblCorrelation.Visible = false;
            }
        }
    }

    private void FilterByCorrelation()
    {
        if (_lblCorrelation?.Tag is not string corrId) return;
        _correlationFilter = corrId;
        if (_txtSearch is not null) _txtSearch.Text = "";  // clear text search
        ApplyFilter();
    }

    // Fields
    private DataGridView dgvEvents      = null!;
    private RichTextBox  txtPayload     = null!;
    private LinkLabel    _lblCorrelation = null!;
}
