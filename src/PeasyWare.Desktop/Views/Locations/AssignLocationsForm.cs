using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

/// <summary>
/// Generic popup for assigning a set of bins to a zone or section.
/// Caller provides the title, the assignment action, and the location query repo.
/// </summary>
public sealed class AssignLocationsForm : Form
{
    private readonly ILocationQueryRepository              _queryRepo;
    private readonly Func<IEnumerable<string>, string?>   _assignAction; // returns error message or null

    private readonly DataGridView _dgv        = new();
    private readonly TextBox      _txtSearch  = new() { PlaceholderText = "Search bin code…  (e.g. type A for floor level)" };
    private readonly Button       _btnAssign  = new() { Text = "Assign", Width = 90, Height = 28, Enabled = false };
    private readonly Button       _btnCancel  = new() { Text = "Close",  Width = 80, Height = 28 };
    private readonly CheckBox     _chkAll     = new() { Text = "Show all locations", AutoSize = true };
    private readonly Label        _lblCount   = new() { AutoSize = true, ForeColor = Color.DimGray };

    private List<LocationDto> _allBins = [];

    public AssignLocationsForm(
        string                                title,
        string                                assignLabel,
        ILocationQueryRepository              queryRepo,
        Func<IEnumerable<string>, string?>    assignAction)
    {
        _queryRepo    = queryRepo;
        _assignAction = assignAction;

        Text            = title;
        Size            = new Size(860, 540);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        _btnAssign.Text = assignLabel;

        BuildLayout();
        ConfigureGrid(_dgv);
        EnableDoubleBuffering(_dgv);

        _dgv.SelectionChanged += (_, _) => UpdateState();
        _txtSearch.TextChanged += (_, _) => ApplyFilter();
        _chkAll.CheckedChanged += (_, _) => { LoadBins(); };

        Load += (_, _) => LoadBins();
    }

    // ==========================================================
    // Layout
    // ==========================================================

    private void BuildLayout()
    {
        // Header
        var pnlHeader = new Panel
        {
            Dock      = DockStyle.Top,
            Height    = 44,
            BackColor = Color.FromArgb(45, 45, 48),
            Padding   = new Padding(14, 12, 0, 0)
        };
        pnlHeader.Controls.Add(new Label
        {
            Text      = Text,
            Dock      = DockStyle.Fill,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize  = false
        });

        // Toolbar row
        var pnlToolbar = new Panel { Dock = DockStyle.Top, Height = 34, Padding = new Padding(8, 4, 8, 0) };
        _txtSearch.Width    = 340;
        _txtSearch.Location = new Point(8, 5);

        _chkAll.Location = new Point(360, 7);

        _lblCount.Location = new Point(530, 8);

        pnlToolbar.Controls.AddRange([_txtSearch, _chkAll, _lblCount]);

        // Grid
        _dgv.Dock = DockStyle.Fill;

        // Footer
        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(8, 10, 8, 0) };
        _btnAssign.Location  = new Point(8, 10);
        _btnCancel.Location  = new Point(106, 10);
        _btnCancel.Click    += (_, _) => Close();
        _btnAssign.Click    += BtnAssign_Click;
        pnlFooter.Controls.AddRange([_btnAssign, _btnCancel]);

        Controls.Add(_dgv);
        Controls.Add(pnlToolbar);
        Controls.Add(pnlFooter);
        Controls.Add(pnlHeader);
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns   = false;
        dgv.SelectionMode         = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect           = true;
        dgv.ReadOnly              = true;
        dgv.AllowUserToAddRows    = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;
        dgv.RowHeadersVisible     = false;
        dgv.AutoSizeColumnsMode   = DataGridViewAutoSizeColumnsMode.Fill;
        dgv.BackgroundColor       = SystemColors.Window;
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Bin",         DataPropertyName = nameof(LocationDto.BinCode),        FillWeight = 10 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Type",        DataPropertyName = nameof(LocationDto.StorageTypeCode), FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Section",     DataPropertyName = nameof(LocationDto.SectionCode),     FillWeight = 7  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Zone",        DataPropertyName = nameof(LocationDto.ZoneCode),        FillWeight = 7  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Cap",         DataPropertyName = nameof(LocationDto.Capacity),        FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Units",       DataPropertyName = nameof(LocationDto.UnitCount),       FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Active",      DataPropertyName = nameof(LocationDto.IsActive),        FillWeight = 4  });

        foreach (DataGridViewColumn col in dgv.Columns)
            col.SortMode = DataGridViewColumnSortMode.NotSortable;

        // Grey out active bins — focus on inactive
        dgv.RowPrePaint += (_, e) =>
        {
            if (e.RowIndex < 0 || e.RowIndex >= dgv.Rows.Count) return;
            if (dgv.Rows[e.RowIndex].DataBoundItem is not LocationDto loc) return;
            dgv.Rows[e.RowIndex].DefaultCellStyle.ForeColor = loc.IsActive
                ? Color.Gray
                : SystemColors.WindowText;
        };
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadBins()
    {
        _allBins = _queryRepo
            .GetLocations(withStockOnly: false)
            .ToList();
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q       = _txtSearch.Text.Trim();
        var showAll = _chkAll.Checked;

        var filtered = _allBins
            .Where(l => showAll || !l.IsActive)
            .Where(l => string.IsNullOrEmpty(q) || l.BinCode.Contains(q, StringComparison.OrdinalIgnoreCase))
            .ToList();

        _dgv.DataSource = null;
        _dgv.DataSource = filtered;

        _lblCount.Text = $"{filtered.Count} location{(filtered.Count == 1 ? "" : "s")}";
        UpdateState();
    }

    private void UpdateState()
    {
        _btnAssign.Enabled = _dgv.SelectedRows.Count > 0;
        var count = _dgv.SelectedRows.Count;
        _btnAssign.Text = count > 0
            ? $"Assign ({count})"
            : "Assign";
    }

    // ==========================================================
    // Assign
    // ==========================================================

    private void BtnAssign_Click(object? sender, EventArgs e)
    {
        var selected = _dgv.SelectedRows
            .Cast<DataGridViewRow>()
            .Select(r => r.DataBoundItem as LocationDto)
            .Where(l => l is not null)
            .Select(l => l!.BinCode)
            .ToList();

        if (selected.Count == 0) return;

        var error = _assignAction(selected);

        if (error is not null)
        {
            MessageBox.Show(this, error, "Assignment Failed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        MessageBox.Show(this,
            $"{selected.Count} location{(selected.Count == 1 ? "" : "s")} assigned successfully.",
            "Done", MessageBoxButtons.OK, MessageBoxIcon.Information);

        // Refresh grid — assignments now show updated section/zone
        LoadBins();
    }

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
