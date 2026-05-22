using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Inbound;

public sealed class InboundDetailForm : Form
{
    private readonly InboundDeliverySummaryDto _delivery;
    private readonly IInboundQueryRepository   _queryRepo;

    private DataGridView _dgvLines = null!;
    private DataGridView _dgvUnits = null!;
    private Label        _lblUnitHeader = null!;

    private List<InboundDeliveryLineDto> _lines = [];
    private int? _selectedLineId = null;

    public InboundDetailForm(
        InboundDeliverySummaryDto delivery,
        IInboundQueryRepository   queryRepo)
    {
        _delivery  = delivery;
        _queryRepo = queryRepo;

        BuildUi();
        Load += (_, _) => LoadLines();
    }

    private void BuildUi()
    {
        Text            = $"Inbound — {_delivery.InboundRef}";
        Size            = new Size(1100, 620);
        MinimumSize     = new Size(800, 480);
        StartPosition   = FormStartPosition.CenterParent;
        FormBorderStyle = FormBorderStyle.Sizable;

        // Header bar
        var lblHeader = new Label
        {
            Text      = BuildHeaderText(),
            Dock      = DockStyle.Top,
            Height    = 52,
            Padding   = new Padding(10, 8, 0, 0),
            Font      = new Font(Font.FontFamily, 9f),
            BackColor = Color.FromArgb(45, 45, 48),
            ForeColor = Color.White
        };

        // Split: lines top, units bottom
        var split = new SplitContainer
        {
            Dock        = DockStyle.Fill,
            Orientation = Orientation.Horizontal,
            SplitterDistance = 260
        };

        // Lines panel
        var pnlLines = new Panel { Dock = DockStyle.Fill };
        var lblLines = new Label
        {
            Text      = "Order lines",
            Dock      = DockStyle.Top,
            Height    = 22,
            Padding   = new Padding(4, 4, 0, 0),
            Font      = new Font(Font.FontFamily, 8.5f, FontStyle.Bold),
            BackColor = SystemColors.ControlLight
        };

        _dgvLines = new DataGridView { Dock = DockStyle.Fill };
        ConfigureLinesGrid(_dgvLines);
        _dgvLines.SelectionChanged += (_, _) => OnLineSelected();
        _dgvLines.CellDoubleClick  += (_, e) => { if (e.RowIndex >= 0) OnLineSelected(); };

        pnlLines.Controls.Add(_dgvLines);
        pnlLines.Controls.Add(lblLines);

        // Units panel
        var pnlUnits = new Panel { Dock = DockStyle.Fill };
        _lblUnitHeader = new Label
        {
            Text      = "Select a line to view units / SSCCs",
            Dock      = DockStyle.Top,
            Height    = 22,
            Padding   = new Padding(4, 4, 0, 0),
            Font      = new Font(Font.FontFamily, 8.5f, FontStyle.Bold),
            BackColor = SystemColors.ControlLight
        };

        _dgvUnits = new DataGridView { Dock = DockStyle.Fill };
        ConfigureUnitsGrid(_dgvUnits);

        pnlUnits.Controls.Add(_dgvUnits);
        pnlUnits.Controls.Add(_lblUnitHeader);

        split.Panel1.Controls.Add(pnlLines);
        split.Panel2.Controls.Add(pnlUnits);

        // Close button
        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 40, Padding = new Padding(8, 6, 8, 6) };
        var btnClose  = new Button { Text = "Close", Width = 80, Height = 28, DialogResult = DialogResult.Cancel };
        btnClose.Anchor = AnchorStyles.Right | AnchorStyles.Top;
        btnClose.Location = new Point(pnlFooter.Width - 96, 6);
        pnlFooter.Controls.Add(btnClose);

        Controls.Add(split);
        Controls.Add(pnlFooter);
        Controls.Add(lblHeader);

        CancelButton = btnClose;

        EnableDoubleBuffering(_dgvLines);
        EnableDoubleBuffering(_dgvUnits);
    }

    private string BuildHeaderText()
    {
        var parts = new List<string>
        {
            $"Ref: {_delivery.InboundRef}",
            $"Status: {_delivery.StatusCode}",
        };
        if (_delivery.SupplierName is not null) parts.Add($"Supplier: {_delivery.SupplierName}");
        if (_delivery.HaulierName  is not null) parts.Add($"Haulier: {_delivery.HaulierName}");
        if (_delivery.ExpectedArrival is not null) parts.Add($"ETA: {_delivery.ExpectedArrival}");
        if (_delivery.InboundMode is not null) parts.Add($"Mode: {_delivery.InboundMode}");
        parts.Add($"Lines: {_delivery.TotalLines}  |  Expected: {_delivery.TotalExpected}  |  Received: {_delivery.TotalReceived}  |  Outstanding: {_delivery.TotalOutstanding}");
        return string.Join("     ", parts[..^1]) + "\n" + parts[^1];
    }

    // ==========================================================
    // Lines grid
    // ==========================================================

    private static void ConfigureLinesGrid(DataGridView dgv)
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
        dgv.BorderStyle           = BorderStyle.None;

        ApplyGridStyle(dgv);

        dgv.Columns.Clear();
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.LineNo),         "#",           3));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.SkuCode),        "SKU",         8));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.SkuDescription), "Description",20));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.BatchNumber),    "Batch",       8));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.BestBeforeDate), "BBE",         7));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.LineStatusCode), "Status",      6));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.ExpectedQty),    "Expected",    6));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.ReceivedQty),    "Received",    6));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.OutstandingQty), "Outstanding", 7));
        dgv.Columns.Add(Col(nameof(InboundDeliveryLineDto.UnitCount),      "Units",       5));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName
                != nameof(InboundDeliveryLineDto.LineStatusCode)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "NEW"  => Color.DimGray,
                "ACT"  => Color.DarkOrange,
                "RCV"  => Color.DarkGreen,
                "CNL"  => Color.Gray,
                _      => Color.Black
            };
        };
    }

    // ==========================================================
    // Units grid
    // ==========================================================

    private static void ConfigureUnitsGrid(DataGridView dgv)
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
        dgv.BorderStyle           = BorderStyle.None;

        ApplyGridStyle(dgv);

        dgv.Columns.Clear();
        dgv.Columns.Add(Col(nameof(InboundUnitDto.Sscc),          "SSCC",          18));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.BatchNumber),    "Batch",          8));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.BestBeforeDate), "BBE",            7));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.Quantity),       "Qty",            4));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.UnitStatus),     "Status",         7));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.ReceivedBin),    "Bin",            7));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.ReceivedBy),     "Received by",    8));
        dgv.Columns.Add(Col(nameof(InboundUnitDto.ReceivedAt),     "Received at",    9));

        dgv.CellFormatting += (_, e) =>
        {
            if (e.RowIndex < 0 || e.ColumnIndex < 0) return;
            if (dgv.Columns[e.ColumnIndex].DataPropertyName
                != nameof(InboundUnitDto.UnitStatus)) return;

            e.CellStyle.ForeColor = e.Value?.ToString() switch
            {
                "RECEIVED"    => Color.DarkGreen,
                "OUTSTANDING" => Color.DimGray,
                "REVERSED"    => Color.Gray,
                _             => Color.Black
            };
        };
    }

    // ==========================================================
    // Data
    // ==========================================================

    private void LoadLines()
    {
        _lines = _queryRepo.GetInboundLines(_delivery.InboundId).ToList();
        _dgvLines.DataSource = null;
        _dgvLines.DataSource = _lines;
        _dgvUnits.DataSource = null;
        _lblUnitHeader.Text  = "Select a line to view units / SSCCs";
    }

    private void OnLineSelected()
    {
        if (_dgvLines.SelectedRows.Count == 0) return;
        if (_dgvLines.SelectedRows[0].DataBoundItem is not InboundDeliveryLineDto line) return;

        _selectedLineId = line.InboundLineId;

        // Only show units pane if there are expected units on this line
        if (line.UnitCount == 0)
        {
            _dgvUnits.DataSource = null;
            _lblUnitHeader.Text  = $"Line {line.LineNo} — {line.SkuCode}  |  Manual receive mode (no pre-advised SSCCs)";
            return;
        }

        _lblUnitHeader.Text = $"Line {line.LineNo} — {line.SkuCode}  |  {line.UnitCount} unit(s)  |  {line.ReceivedQty}/{line.ExpectedQty} received";

        var units = _queryRepo.GetInboundUnits(line.InboundLineId).ToList();
        _dgvUnits.DataSource = null;
        _dgvUnits.DataSource = units;
    }

    // ==========================================================
    // Helpers
    // ==========================================================

    private static void ApplyGridStyle(DataGridView dgv)
    {
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor          = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor          = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font               = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor              = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor              = Color.Black;
    }

    private static DataGridViewTextBoxColumn Col(string prop, string header, int fill) =>
        new() { DataPropertyName = prop, HeaderText = header, FillWeight = fill };

    private static void EnableDoubleBuffering(DataGridView dgv) =>
        typeof(DataGridView)
            .GetProperty("DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
}
