using PeasyWare.Application.Contexts;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Infrastructure.Ui;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Counting;

/// <summary>
/// Counting: the counts that still need someone (top), and for the selected
/// count the pallets found in bins the system believed were empty and the
/// bins themselves (below).
///
/// By default only counts that need attention are listed: in progress, and
/// "Needs review" - finished, but they found something a person has to deal
/// with (a pallet that was shipped, one the system doesn't know, one the move
/// rules wouldn't let the count relocate). "Show all counts" brings back the
/// history.
///
/// A manager / admin (counts.review) marks a count reviewed once the findings
/// are dealt with, recording a note on what was done. Counts are carried out
/// in the CLI; this screen never changes stock.
/// </summary>
public sealed class CountsView : BaseView, IToolbarAware
{
    private readonly ICountQueryRepository   _repo;
    private readonly ICountCommandRepository _commandRepo;
    private readonly bool                    _canReview;

    private readonly SplitContainer _split       = new();
    private readonly DataGridView   _dgvSessions = new();
    private readonly DataGridView   _dgvLines    = new();
    private readonly DataGridView   _dgvFindings = new();
    private readonly TabControl     _tabs        = new();
    private readonly TabPage        _tabFindings = new("Findings");
    private readonly TabPage        _tabLines    = new("Bins");
    private readonly Label          _lblDetail   = new();
    private readonly ToolTip        _tip         = new();

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnShowAll;
    private ToolStripButton? _btnReviewOnly;
    private ToolStripButton? _btnReview;

    private List<CountSessionDto> _sessions = [];
    private List<CountLineDto>    _lines    = [];
    private List<CountFindingDto> _findings = [];

    // Suppresses selection-change reloads while a grid is being (re)bound
    private bool _binding;

    public CountsView(
        SessionContext          session,
        ICountQueryRepository   repo,
        ICountCommandRepository commandRepo)
    {
        _repo        = repo;
        _commandRepo = commandRepo;

        // RBAC: marking a count reviewed is gated on counts.review (manager +
        // admin). Computed once - session lifetime is static. The procedure
        // enforces it too; this only greys the button.
        _canReview = session.HasPermission("counts.review");

        ConfigureSessionsGrid(_dgvSessions);
        ConfigureLinesGrid(_dgvLines);
        ConfigureFindingsGrid(_dgvFindings);

        foreach (var grid in new[] { _dgvSessions, _dgvLines, _dgvFindings })
        {
            grid.Dock = DockStyle.Fill;
            EnableDoubleBuffering(grid);
        }

        _tabLines.Controls.Add(_dgvLines);
        _tabFindings.Controls.Add(_dgvFindings);

        _tabs.Dock = DockStyle.Fill;
        _tabs.TabPages.Add(_tabFindings);
        _tabs.TabPages.Add(_tabLines);

        _lblDetail.Dock         = DockStyle.Top;
        _lblDetail.Height       = 26;
        _lblDetail.TextAlign    = ContentAlignment.MiddleLeft;
        _lblDetail.Padding      = new Padding(4, 0, 0, 0);
        _lblDetail.Font         = new Font(Font, FontStyle.Bold);
        _lblDetail.AutoEllipsis = true;

        // Fill first, then Top - WinForms docks in reverse add order
        var detailPanel = new Panel { Dock = DockStyle.Fill };
        detailPanel.Controls.Add(_tabs);
        detailPanel.Controls.Add(_lblDetail);

        _split.Dock        = DockStyle.Fill;
        _split.Orientation = Orientation.Horizontal;
        _split.Panel1.Controls.Add(_dgvSessions);
        _split.Panel2.Controls.Add(detailPanel);

        Controls.Add(_split);

        _dgvSessions.SelectionChanged += (_, _) =>
        {
            if (_binding) return;

            Execute(LoadDetail);
            UpdateToolbarState();
        };

        Load += (_, _) =>
        {
            SetSplitterDistance();
            Execute(LoadSessions);
        };
    }

    private void SetSplitterDistance()
    {
        // Sessions need less room than their detail; guard against the host
        // not having its final size yet (SplitterDistance throws when out of range)
        try
        {
            var wanted = Math.Max(100, _split.Height / 3);
            if (wanted < _split.Height - 100)
                _split.SplitterDistance = wanted;
        }
        catch (InvalidOperationException) { }
    }

    // ==========================================================
    // IToolbarAware
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();

        _btnRefresh = new ToolStripButton("Refresh") { DisplayStyle = ToolStripItemDisplayStyle.Text };
        _btnRefresh.Click += Wrap(LoadSessions);

        // Default (unchecked) = only counts that still need someone
        _btnShowAll = new ToolStripButton("Show all counts")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            CheckOnClick = true
        };
        _btnShowAll.CheckedChanged += (_, _) => Execute(LoadSessions);

        _btnReviewOnly = new ToolStripButton("Findings: needs review only")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            CheckOnClick = true
        };
        _btnReviewOnly.CheckedChanged += (_, _) => BindFindings();

        _btnReview = new ToolStripButton("Mark reviewed…")
        {
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            Enabled      = false
        };
        _btnReview.Click += Wrap(ReviewSelected);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnShowAll);
        toolStrip.Items.Add(_btnReviewOnly);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnReview);

        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        _btnReview?.GateBy(_canReview && SelectedSession()?.AwaitsReview == true);
    }

    // ==========================================================
    // Data
    // ==========================================================

    private CountSessionDto? SelectedSession() =>
        _dgvSessions.CurrentRow?.DataBoundItem as CountSessionDto;

    private bool ShowingAll => _btnShowAll?.Checked == true;

    private void LoadSessions()
    {
        var keepId = SelectedSession()?.CountId;

        _sessions = _repo.GetSessions(needsAttentionOnly: !ShowingAll).ToList();

        _binding = true;
        try
        {
            _dgvSessions.DataSource = null;
            _dgvSessions.DataSource = _sessions;

            if (_sessions.Count > 0)
            {
                var index = keepId is null ? 0 : _sessions.FindIndex(s => s.CountId == keepId);
                if (index < 0) index = 0;

                _dgvSessions.ClearSelection();
                _dgvSessions.Rows[index].Selected = true;
                _dgvSessions.CurrentCell = _dgvSessions.Rows[index].Cells[0];
            }
        }
        finally
        {
            _binding = false;
        }

        LoadDetail();
        UpdateToolbarState();
    }

    private void LoadDetail()
    {
        var session = SelectedSession();

        if (session is null)
        {
            _lines    = [];
            _findings = [];

            SetDetailText(ShowingAll
                ? "No counts yet."
                : "Nothing needs attention - every count is finished and reviewed. " +
                  "Use \"Show all counts\" for the history.");
        }
        else
        {
            _lines    = _repo.GetLines(session.CountId).ToList();
            _findings = _repo.GetFindings(session.CountId).ToList();

            var text =
                $"Count #{session.CountId}  —  {CountTypeText(session.CountTypeCode)}  —  " +
                $"{session.StorageTypeCode}  —  {StatusText(session.StatusCode)}";

            if (session.ReviewedAt is not null)
            {
                text += $"  —  reviewed by {session.ReviewedBy} " +
                        $"{session.ReviewedAt:dd/MM/yyyy HH:mm}: {session.ReviewNote}";
            }

            SetDetailText(text);
        }

        BindLines();
        BindFindings();
    }

    private void SetDetailText(string text)
    {
        _lblDetail.Text = text;
        _tip.SetToolTip(_lblDetail, text);   // the review note can be longer than the label
    }

    private void BindLines()
    {
        _dgvLines.DataSource = null;
        _dgvLines.DataSource = _lines;
        _tabLines.Text = $"Bins ({_lines.Count})";
    }

    private void BindFindings()
    {
        var data = _btnReviewOnly?.Checked == true
            ? _findings.Where(f => f.NeedsReview).ToList()
            : _findings;

        _dgvFindings.DataSource = null;
        _dgvFindings.DataSource = data;

        var review = _findings.Count(f => f.NeedsReview);

        _tabFindings.Text = review > 0
            ? $"Findings ({_findings.Count}, {review} to review)"
            : $"Findings ({_findings.Count})";
    }

    // ==========================================================
    // Review
    // ==========================================================

    private void ReviewSelected()
    {
        var session = SelectedSession();

        if (session is null || !session.AwaitsReview)
            return;

        using var dialog = new CountReviewDialog(session, _findings);

        if (dialog.ShowDialog(this) != DialogResult.OK)
            return;

        var result = _commandRepo.Review(session.CountId, dialog.Note);

        if (!result.Success)
        {
            MessageBox.Show(result.FriendlyMessage, "Count review",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        // Reviewed counts drop off the default (needs-attention) list
        LoadSessions();
    }

    // ==========================================================
    // Display text
    // ==========================================================

    private static string CountTypeText(string code) => code switch
    {
        "EMPTY_BIN" => "Empty bin check",
        _           => code
    };

    private static string StatusText(string code) => code switch
    {
        "OPEN"     => "In progress",
        "REVIEW"   => "Needs review",
        "COMPLETE" => "Complete",
        "CLOSED"   => "Closed",
        _          => code
    };

    private static string LineStatusText(string code) => code switch
    {
        "PENDING"         => "Pending",
        "CONFIRMED_EMPTY" => "Confirmed empty",
        "STOCK_FOUND"     => "Stock found",
        "OCCUPIED_SINCE"  => "Filled since start",
        _                 => code
    };

    private static string FindingText(string code) => code switch
    {
        "RECORD_CORRECTED" => "Record corrected",
        "NOT_CORRECTED"    => "Not corrected",
        "UNKNOWN_UNIT"     => "Unknown pallet",
        _                  => code
    };

    // ==========================================================
    // Grids
    // ==========================================================

    private static void StyleGrid(DataGridView dgv)
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
    }

    private static void ConfigureSessionsGrid(DataGridView dgv)
    {
        StyleGrid(dgv);

        dgv.Columns.Add(Col(nameof(CountSessionDto.CountId),          "Count #",      5));
        dgv.Columns.Add(Col(nameof(CountSessionDto.CountTypeCode),    "Type",         9));
        dgv.Columns.Add(Col(nameof(CountSessionDto.StorageTypeCode),  "Storage type", 8));
        dgv.Columns.Add(Col(nameof(CountSessionDto.StatusCode),       "Status",       9));
        dgv.Columns.Add(Col(nameof(CountSessionDto.StartedAt),        "Started",     11, "dd/MM/yyyy HH:mm"));
        dgv.Columns.Add(Col(nameof(CountSessionDto.StartedBy),        "Started by",   7));
        dgv.Columns.Add(Col(nameof(CountSessionDto.CompletedAt),      "Finished",    11, "dd/MM/yyyy HH:mm"));
        dgv.Columns.Add(Col(nameof(CountSessionDto.CompletedBy),      "Finished by",  7));
        dgv.Columns.Add(Col(nameof(CountSessionDto.TotalBins),        "Bins",         5, null, right: true));
        dgv.Columns.Add(Col(nameof(CountSessionDto.PendingBins),      "Pending",      6, null, right: true));
        dgv.Columns.Add(Col(nameof(CountSessionDto.ConfirmedEmpty),   "Empty",        5, null, right: true));
        dgv.Columns.Add(Col(nameof(CountSessionDto.StockFound),       "Stock found",  7, null, right: true));
        dgv.Columns.Add(Col(nameof(CountSessionDto.OccupiedSince),    "Filled since", 7, null, right: true));
        dgv.Columns.Add(Col(nameof(CountSessionDto.FindingsToReview), "To review",    7, null, right: true));
        dgv.Columns.Add(Col(nameof(CountSessionDto.ReviewedBy),       "Reviewed by",  8));
        dgv.Columns.Add(Col(nameof(CountSessionDto.ReviewNote),       "Review note", 20));

        // Fill mode gives a 5-weight column almost nothing - keep the header readable
        dgv.Columns[0].MinimumWidth = 65;

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;

            switch (dgv.Columns[e.ColumnIndex].DataPropertyName)
            {
                case nameof(CountSessionDto.CountTypeCode):
                    e.Value = CountTypeText(e.Value?.ToString() ?? "");
                    e.FormattingApplied = true;
                    break;

                case nameof(CountSessionDto.StatusCode):
                    var code = e.Value?.ToString() ?? "";
                    e.Value = StatusText(code);
                    e.FormattingApplied = true;
                    e.CellStyle.ForeColor = code switch
                    {
                        "OPEN"     => Color.DarkOrange,
                        "REVIEW"   => Color.Firebrick,
                        "COMPLETE" => Color.DarkGreen,
                        "CLOSED"   => Color.Gray,
                        _          => Color.Black
                    };
                    e.CellStyle.Font = new Font(dgv.Font, FontStyle.Bold);
                    break;

                case nameof(CountSessionDto.StockFound):
                    if (e.Value is int found && found > 0)
                    {
                        e.CellStyle.ForeColor = Color.DarkRed;
                        e.CellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
                    }
                    break;

                case nameof(CountSessionDto.ReviewNote):
                    // The note can be longer than the column: hovering shows all of it,
                    // with who wrote it and when
                    if (dgv.Rows[e.RowIndex].DataBoundItem is CountSessionDto { ReviewedAt: not null } reviewed)
                    {
                        dgv.Rows[e.RowIndex].Cells[e.ColumnIndex].ToolTipText =
                            $"Reviewed by {reviewed.ReviewedBy} on {reviewed.ReviewedAt:dd/MM/yyyy HH:mm}\n\n{reviewed.ReviewNote}";
                    }
                    break;

                case nameof(CountSessionDto.FindingsToReview):
                    // Red while it is still waiting on someone; plain once reviewed
                    if (e.Value is int toReview && toReview > 0 &&
                        dgv.Rows[e.RowIndex].DataBoundItem is CountSessionDto { AwaitsReview: true })
                    {
                        e.CellStyle.ForeColor = Color.Firebrick;
                        e.CellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
                    }
                    break;
            }
        };

        // Counts that still need someone stand out: in progress (amber),
        // waiting for review (red)
        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not CountSessionDto row) return;

            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = row.StatusCode switch
            {
                "OPEN"   => Color.FromArgb(255, 248, 225),
                "REVIEW" => Color.FromArgb(255, 235, 235),
                _        => SystemColors.Window
            };
        };
    }

    private static void ConfigureLinesGrid(DataGridView dgv)
    {
        StyleGrid(dgv);

        dgv.Columns.Add(Col(nameof(CountLineDto.BinCode),        "Bin",           12));
        dgv.Columns.Add(Col(nameof(CountLineDto.ZoneCode),       "Zone",           8));
        dgv.Columns.Add(Col(nameof(CountLineDto.LineStatusCode), "Result",        16));
        dgv.Columns.Add(Col(nameof(CountLineDto.CountedAt),      "Counted",       16, "dd/MM/yyyy HH:mm:ss"));
        dgv.Columns.Add(Col(nameof(CountLineDto.CountedBy),      "Counted by",    10));
        dgv.Columns.Add(Col(nameof(CountLineDto.FindingCount),   "Pallets found",  9, null, right: true));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(CountLineDto.LineStatusCode)) return;

            e.Value = LineStatusText(e.Value?.ToString() ?? "");
            e.FormattingApplied = true;
        };

        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not CountLineDto row) return;

            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = row.LineStatusCode switch
            {
                "STOCK_FOUND"    => Color.FromArgb(255, 240, 215),
                "OCCUPIED_SINCE" => Color.FromArgb(235, 240, 250),
                _                => SystemColors.Window
            };
        };
    }

    private static void ConfigureFindingsGrid(DataGridView dgv)
    {
        StyleGrid(dgv);

        dgv.Columns.Add(Col(nameof(CountFindingDto.BinCode),         "Bin",                8));
        dgv.Columns.Add(Col(nameof(CountFindingDto.ScannedRef),      "Pallet",            16));
        dgv.Columns.Add(Col(nameof(CountFindingDto.SkuCode),         "SKU",                8));
        dgv.Columns.Add(Col(nameof(CountFindingDto.FindingCode),     "Result",            11));
        dgv.Columns.Add(Col(nameof(CountFindingDto.ReasonMessage),   "Why not corrected", 22));
        dgv.Columns.Add(Col(nameof(CountFindingDto.ShipmentRef),     "Left on",           10));
        dgv.Columns.Add(Col(nameof(CountFindingDto.ShippedAt),       "Shipped",           11, "dd/MM/yyyy HH:mm"));
        dgv.Columns.Add(Col(nameof(CountFindingDto.OrderRef),        "Order",             10));
        dgv.Columns.Add(Col(nameof(CountFindingDto.CustomerName),    "Customer",          12));
        dgv.Columns.Add(Col(nameof(CountFindingDto.PreviousBinCode), "System had it in",   9));
        dgv.Columns.Add(Col(nameof(CountFindingDto.FoundAt),         "Found",             12, "dd/MM/yyyy HH:mm"));
        dgv.Columns.Add(Col(nameof(CountFindingDto.FoundBy),         "By",                 8));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName != nameof(CountFindingDto.FindingCode)) return;

            e.Value = FindingText(e.Value?.ToString() ?? "");
            e.FormattingApplied = true;
            e.CellStyle.Font = new Font(dgv.Font, FontStyle.Bold);
        };

        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not CountFindingDto row) return;

            dgv.Rows[e.RowIndex].DefaultCellStyle.BackColor = row.FindingCode switch
            {
                "RECORD_CORRECTED" => Color.FromArgb(240, 255, 240),
                "NOT_CORRECTED"    => Color.FromArgb(255, 240, 215),
                "UNKNOWN_UNIT"     => Color.FromArgb(255, 235, 235),
                _                  => SystemColors.Window
            };
        };
    }

    private static DataGridViewTextBoxColumn Col(
        string  prop,
        string  header,
        int     fill,
        string? format = null,
        bool    right  = false)
    {
        var col = new DataGridViewTextBoxColumn
        {
            DataPropertyName = prop,
            HeaderText       = header,
            FillWeight       = fill,
            SortMode         = DataGridViewColumnSortMode.NotSortable
        };

        if (format is not null || right)
        {
            col.DefaultCellStyle = new DataGridViewCellStyle
            {
                Format    = format ?? "",
                Alignment = right
                    ? DataGridViewContentAlignment.MiddleRight
                    : DataGridViewContentAlignment.NotSet
            };
        }

        return col;
    }

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
