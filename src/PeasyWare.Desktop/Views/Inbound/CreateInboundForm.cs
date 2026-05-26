using PeasyWare.Application;
using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Inbound;

/// <summary>
/// Three-stage create form:
///   Stage 1 — Delivery header (ref, supplier, haulier, ETA, mode)
///   Stage 2 — Lines (SKU, qty, batch, BBE)
///   Stage 3 — Expected units / SSCCs per line (SSCC mode only)
/// </summary>
public sealed class CreateInboundForm : Form
{
    private readonly IInboundCommandRepository _commandRepo;
    private readonly ISkuQueryRepository       _skuRepo;
    private readonly IPartyQueryRepository     _partyRepo;

    // ── Stage 1 controls ──────────────────────────────────────────────────
    private readonly TextBox        _txtRef          = new();
    private readonly ComboBox       _cmbSupplier     = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox       _cmbHaulier      = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly DateTimePicker _dtpArrival      = new() { Format = DateTimePickerFormat.Custom, CustomFormat = "dd/MM/yyyy HH:mm", ShowUpDown = false };
    private readonly CheckBox       _chkArrivalKnown = new() { Text = "Expected arrival date known", Checked = true };
    private readonly ComboBox       _cmbMode         = new() { DropDownStyle = ComboBoxStyle.DropDownList };

    // ── Stage 2 controls ──────────────────────────────────────────────────
    private readonly DataGridView   _dgvLines        = new();
    private readonly ComboBox       _cmbLineSku      = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown  _nudQty          = new() { Minimum = 1, Maximum = 99999, Value = 1 };
    private readonly TextBox        _txtBatch        = new();
    private readonly DateTimePicker _dtpBBE          = new() { Format = DateTimePickerFormat.Short };
    private readonly CheckBox       _chkBBEKnown     = new() { Text = "Has best before date", Checked = false };

    // ── Stage 3 controls ──────────────────────────────────────────────────
    private readonly ComboBox       _cmbLinePicker   = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly DataGridView   _dgvUnits        = new();
    private readonly TextBox        _txtSscc         = new();
    private readonly NumericUpDown  _nudUnitQty      = new() { Minimum = 1, Maximum = 99999, Value = 1 };
    private readonly TextBox        _txtUnitBatch    = new();
    private readonly DateTimePicker _dtpUnitBBE      = new() { Format = DateTimePickerFormat.Short };
    private readonly CheckBox       _chkUnitBBE      = new() { Text = "Has BBE", Checked = false };

    // ── Navigation ────────────────────────────────────────────────────────
    private readonly TabControl _tabs      = new() { Appearance = TabAppearance.FlatButtons };
    private readonly Button     _btnBack   = new() { Text = "← Back",   Width = 100, Height = 30 };
    private readonly Button     _btnNext   = new() { Text = "Next →",   Width = 100, Height = 30 };
    private readonly Button     _btnFinish = new() { Text = "✓ Finish", Width = 100, Height = 30, Enabled = false };
    private readonly Button     _btnCancel = new() { Text = "Cancel",   Width = 100, Height = 30, DialogResult = DialogResult.Cancel };

    // ── Data ──────────────────────────────────────────────────────────────
    private string? _createdInboundRef;
    private readonly List<LineEntry> _lines = [];
    private readonly Dictionary<int, List<UnitEntry>> _units = [];  // lineIndex → units
    private List<SkuDto>    _skus    = [];
    private List<PartyDto>  _parties = [];

    public string? CreatedInboundRef => _createdInboundRef;

    private record LineEntry(string SkuCode, string SkuDesc, int Qty, string? Batch, DateTime? BBE);
    private record UnitEntry(string Sscc, int Qty, string? Batch, DateTime? BBE);

    // ─────────────────────────────────────────────────────────────────────

    public CreateInboundForm(
        IInboundCommandRepository commandRepo,
        ISkuQueryRepository       skuRepo,
        IPartyQueryRepository     partyRepo)
    {
        _commandRepo = commandRepo;
        _skuRepo     = skuRepo;
        _partyRepo   = partyRepo;

        Text            = "Create Inbound Delivery";
        Size            = new Size(740, 560);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        CancelButton    = _btnCancel;

        BuildLayout();
        LoadLookups();
        SuggestRef();
        UpdateNav();
    }

    // ==========================================================
    // Layout
    // ==========================================================

    private void BuildLayout()
    {
        // Dark header
        var pnlHeader = new Panel
        {
            Dock      = DockStyle.Top,
            Height    = 48,
            BackColor = Color.FromArgb(45, 45, 48),
            Padding   = new Padding(14, 10, 0, 0)
        };
        var lblTitle = new Label
        {
            Text      = "New Inbound Delivery",
            Dock      = DockStyle.Fill,
            Font      = new Font(Font.FontFamily, 11f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize  = false
        };
        pnlHeader.Controls.Add(lblTitle);

        // Tabs (used as pages — tab headers hidden via FlatButtons + zero height)
        _tabs.Dock        = DockStyle.Fill;
        _tabs.ItemSize    = new Size(0, 1);   // hide headers
        _tabs.SizeMode    = TabSizeMode.Fixed;

        var tabHeader = new TabPage { Padding = new Padding(12) };
        var tabLines  = new TabPage { Padding = new Padding(12) };
        var tabUnits  = new TabPage { Padding = new Padding(12) };

        BuildHeaderTab(tabHeader);
        BuildLinesTab(tabLines);
        BuildUnitsTab(tabUnits);

        _tabs.TabPages.Add(tabHeader);
        _tabs.TabPages.Add(tabLines);
        _tabs.TabPages.Add(tabUnits);

        // Footer
        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(12, 10, 12, 0) };
        _btnBack.Location   = new Point(12,   10);
        _btnNext.Location   = new Point(120,  10);
        _btnFinish.Location = new Point(228,  10);
        _btnCancel.Location = new Point(pnlFooter.Width - 112, 10);
        _btnCancel.Anchor   = AnchorStyles.Right | AnchorStyles.Top;

        _btnBack.Click   += (_, _) => Navigate(-1);
        _btnNext.Click   += (_, _) => Navigate(+1);
        _btnFinish.Click += (_, _) => Finish();

        pnlFooter.Controls.AddRange([_btnBack, _btnNext, _btnFinish, _btnCancel]);

        Controls.Add(_tabs);
        Controls.Add(pnlFooter);
        Controls.Add(pnlHeader);
    }

    // ── Stage 1: Header ───────────────────────────────────────────────────

    private void BuildHeaderTab(TabPage tab)
    {
        var table = MakeTable(8);
        int row   = 0;

        _cmbMode.Items.AddRange(["SSCC", "MANUAL"]);
        _cmbMode.SelectedIndex = 0;

        _chkArrivalKnown.CheckedChanged += (_, _) => _dtpArrival.Enabled = _chkArrivalKnown.Checked;

        AddRow(table, row++, "Inbound Ref *",  _txtRef);
        AddRow(table, row++, "Supplier *",      _cmbSupplier);
        AddRow(table, row++, "Haulier",         _cmbHaulier);
        AddRow(table, row++, "Mode",            _cmbMode);
        AddRow(table, row++, "Known ETA",       _chkArrivalKnown);
        AddRow(table, row++, "Expected Arrival",_dtpArrival);

        tab.Controls.Add(table);

        var lblHint = new Label
        {
            Text      = "Step 1 of 3 — Delivery header",
            Dock      = DockStyle.Bottom,
            Height    = 22,
            TextAlign = ContentAlignment.BottomLeft,
            ForeColor = SystemColors.GrayText,
            Font      = new Font(Font.FontFamily, 8f)
        };
        tab.Controls.Add(lblHint);
    }

    // ── Stage 2: Lines ────────────────────────────────────────────────────

    private void BuildLinesTab(TabPage tab)
    {
        // Lines grid
        _dgvLines.Dock              = DockStyle.None;
        _dgvLines.Size              = new Size(700, 200);
        _dgvLines.Location          = new Point(0, 0);
        _dgvLines.AutoGenerateColumns = false;
        _dgvLines.SelectionMode     = DataGridViewSelectionMode.FullRowSelect;
        _dgvLines.AllowUserToAddRows = false;
        _dgvLines.ReadOnly          = true;
        _dgvLines.RowHeadersVisible = false;
        _dgvLines.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        _dgvLines.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SKU",         DataPropertyName = "SkuCode",  FillWeight = 8 });
        _dgvLines.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = "SkuDesc",  FillWeight = 20 });
        _dgvLines.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Qty",         DataPropertyName = "Qty",      FillWeight = 5 });
        _dgvLines.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Batch",       DataPropertyName = "Batch",    FillWeight = 10 });
        _dgvLines.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "BBE",         DataPropertyName = "BBE",      FillWeight = 7 });

        // Add line controls
        var pnlAdd = new Panel { Location = new Point(0, 208), Size = new Size(700, 62), BorderStyle = BorderStyle.FixedSingle };

        _cmbLineSku.Size     = new Size(200, 24);
        _cmbLineSku.Location = new Point(4, 6);
        _cmbLineSku.DisplayMember = "Display";

        _nudQty.Size     = new Size(70, 24);
        _nudQty.Location = new Point(210, 6);

        _txtBatch.Size        = new Size(100, 24);
        _txtBatch.Location    = new Point(288, 6);
        _txtBatch.PlaceholderText = "Batch";

        _chkBBEKnown.Location = new Point(400, 8);
        _chkBBEKnown.AutoSize = true;
        _chkBBEKnown.CheckedChanged += (_, _) => _dtpBBE.Visible = _chkBBEKnown.Checked;

        _dtpBBE.Size     = new Size(100, 24);
        _dtpBBE.Location = new Point(510, 6);
        _dtpBBE.Visible  = false;

        var btnAdd = new Button { Text = "+ Add line", Size = new Size(90, 24), Location = new Point(4, 32) };
        btnAdd.Click += AddLine;

        var btnRemove = new Button { Text = "Remove", Size = new Size(80, 24), Location = new Point(100, 32) };
        btnRemove.Click += RemoveLine;

        pnlAdd.Controls.AddRange([_cmbLineSku, _nudQty, _txtBatch, _chkBBEKnown, _dtpBBE, btnAdd, btnRemove]);

        tab.Controls.Add(_dgvLines);
        tab.Controls.Add(pnlAdd);

        var lblHint = new Label
        {
            Text      = "Step 2 of 3 — Order lines",
            Dock      = DockStyle.Bottom,
            Height    = 22,
            TextAlign = ContentAlignment.BottomLeft,
            ForeColor = SystemColors.GrayText,
            Font      = new Font(Font.FontFamily, 8f)
        };
        tab.Controls.Add(lblHint);
    }

    // ── Stage 3: Units (SSCC mode) ────────────────────────────────────────

    private void BuildUnitsTab(TabPage tab)
    {
        var lblLine = new Label { Text = "Line:", Location = new Point(0, 4), AutoSize = true };
        _cmbLinePicker.Location = new Point(40, 0);
        _cmbLinePicker.Size     = new Size(280, 24);
        _cmbLinePicker.DisplayMember = "Display";
        _cmbLinePicker.SelectedIndexChanged += (_, _) => RefreshUnitsGrid();

        _dgvUnits.Location  = new Point(0, 32);
        _dgvUnits.Size      = new Size(700, 180);
        _dgvUnits.AutoGenerateColumns = false;
        _dgvUnits.SelectionMode     = DataGridViewSelectionMode.FullRowSelect;
        _dgvUnits.AllowUserToAddRows = false;
        _dgvUnits.ReadOnly          = true;
        _dgvUnits.RowHeadersVisible = false;
        _dgvUnits.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        _dgvUnits.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SSCC",  DataPropertyName = "Sscc",  FillWeight = 18 });
        _dgvUnits.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Qty",   DataPropertyName = "Qty",   FillWeight = 4 });
        _dgvUnits.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Batch", DataPropertyName = "Batch", FillWeight = 10 });
        _dgvUnits.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "BBE",   DataPropertyName = "BBE",   FillWeight = 7 });

        // Add unit controls
        var pnlAdd = new Panel { Location = new Point(0, 220), Size = new Size(700, 62), BorderStyle = BorderStyle.FixedSingle };

        _txtSscc.Size             = new Size(160, 24);
        _txtSscc.Location         = new Point(4, 6);
        _txtSscc.PlaceholderText  = "SSCC (18 digits)";

        _nudUnitQty.Size     = new Size(70, 24);
        _nudUnitQty.Location = new Point(170, 6);

        _txtUnitBatch.Size         = new Size(100, 24);
        _txtUnitBatch.Location     = new Point(248, 6);
        _txtUnitBatch.PlaceholderText = "Batch (optional)";

        _chkUnitBBE.Location = new Point(356, 8);
        _chkUnitBBE.AutoSize = true;
        _chkUnitBBE.CheckedChanged += (_, _) => _dtpUnitBBE.Visible = _chkUnitBBE.Checked;

        _dtpUnitBBE.Size     = new Size(100, 24);
        _dtpUnitBBE.Location = new Point(430, 6);
        _dtpUnitBBE.Visible  = false;

        var btnAddUnit = new Button { Text = "+ Add SSCC", Size = new Size(90, 24), Location = new Point(4, 32) };
        btnAddUnit.Click += AddUnit;

        var btnRemoveUnit = new Button { Text = "Remove", Size = new Size(80, 24), Location = new Point(100, 32) };
        btnRemoveUnit.Click += RemoveUnit;

        pnlAdd.Controls.AddRange([_txtSscc, _nudUnitQty, _txtUnitBatch, _chkUnitBBE, _dtpUnitBBE, btnAddUnit, btnRemoveUnit]);

        tab.Controls.Add(lblLine);
        tab.Controls.Add(_cmbLinePicker);
        tab.Controls.Add(_dgvUnits);
        tab.Controls.Add(pnlAdd);

        var lblHint = new Label
        {
            Text      = "Step 3 of 3 — Expected SSCCs (optional — skip if MANUAL mode or pre-advice not available)",
            Dock      = DockStyle.Bottom,
            Height    = 22,
            TextAlign = ContentAlignment.BottomLeft,
            ForeColor = SystemColors.GrayText,
            Font      = new Font(Font.FontFamily, 8f)
        };
        tab.Controls.Add(lblHint);
    }

    // ==========================================================
    // Lookups
    // ==========================================================

    private void LoadLookups()
    {
        _skus    = _skuRepo.GetAll().ToList();
        _parties = _partyRepo.GetParties().ToList();

        // Suppliers
        _cmbSupplier.Items.Add(new PartyLookup(null, "(select supplier)"));
        foreach (var p in _parties.Where(p => p.IsSupplier))
            _cmbSupplier.Items.Add(new PartyLookup(p.PartyCode, $"{p.DisplayName} ({p.PartyCode})"));
        _cmbSupplier.DisplayMember = "Display";
        _cmbSupplier.SelectedIndex = 0;

        // Hauliers
        _cmbHaulier.Items.Add(new PartyLookup(null, "(none)"));
        foreach (var p in _parties.Where(p => p.IsHaulier))
            _cmbHaulier.Items.Add(new PartyLookup(p.PartyCode, $"{p.DisplayName} ({p.PartyCode})"));
        _cmbHaulier.DisplayMember = "Display";
        _cmbHaulier.SelectedIndex = 0;

        // SKUs for line picker
        _cmbLineSku.Items.Add(new SkuLookup(null, "(select SKU)"));
        foreach (var s in _skus.Where(s => s.IsActive))
            _cmbLineSku.Items.Add(new SkuLookup(s.SkuCode, $"{s.SkuCode} – {s.SkuDescription}"));
        _cmbLineSku.DisplayMember = "Display";
        _cmbLineSku.SelectedIndex = 0;
    }

    private void SuggestRef()
    {
        var year = DateTime.Today.Year;
        _txtRef.Text = $"INB-{year}-";
        _txtRef.SelectionStart = _txtRef.Text.Length;
    }

    // ==========================================================
    // Navigation
    // ==========================================================

    private void Navigate(int direction)
    {
        var current = _tabs.SelectedIndex;
        var target  = current + direction;

        // Validate before advancing
        if (direction > 0 && !ValidateStage(current))
            return;

        // Skip stage 3 if MANUAL mode
        if (target == 2 && _cmbMode.SelectedItem?.ToString() == "MANUAL")
        {
            if (direction > 0) { Finish(); return; }
            else target = 1;
        }

        if (target < 0 || target >= _tabs.TabCount) return;

        _tabs.SelectedIndex = target;

        // Populate line picker when entering stage 3
        if (target == 2) PopulateLinePicker();

        // Enable Finish on stage 3, or stage 2 if MANUAL mode
        _btnFinish.Enabled = _tabs.SelectedIndex == 2 ||
                             (_tabs.SelectedIndex == 1 && _cmbMode.SelectedItem?.ToString() == "MANUAL");

        UpdateNav();
    }

    private void UpdateNav()
    {
        var i = _tabs.SelectedIndex;
        _btnBack.Enabled = i > 0;
        _btnNext.Enabled = i < _tabs.TabCount - 1;
        _btnNext.Text    = i == 1 && _cmbMode.SelectedItem?.ToString() == "MANUAL"
            ? "Finish →"
            : "Next →";
    }

    private bool ValidateStage(int stage)
    {
        if (stage == 0)
        {
            if (string.IsNullOrWhiteSpace(_txtRef.Text))
            { Msg("Inbound reference is required."); return false; }

            if (_cmbSupplier.SelectedItem is not PartyLookup s || s.Code is null)
            { Msg("Please select a supplier."); return false; }
        }

        if (stage == 1 && _lines.Count == 0)
        { Msg("At least one order line is required."); return false; }

        return true;
    }

    // ==========================================================
    // Line management
    // ==========================================================

    private void AddLine(object? sender, EventArgs e)
    {
        if (_cmbLineSku.SelectedItem is not SkuLookup sku || sku.Code is null)
        { Msg("Please select a SKU."); return; }

        var bbe = _chkBBEKnown.Checked ? (DateTime?)_dtpBBE.Value.Date : null;
        var batch = string.IsNullOrWhiteSpace(_txtBatch.Text) ? null : _txtBatch.Text.Trim();

        _lines.Add(new LineEntry(sku.Code, sku.Display, (int)_nudQty.Value, batch, bbe));
        RefreshLinesGrid();

        _cmbLineSku.SelectedIndex = 0;
        _nudQty.Value             = 1;
        _txtBatch.Clear();
        _chkBBEKnown.Checked      = false;
        _btnFinish.Enabled        = _cmbMode.SelectedItem?.ToString() == "MANUAL" && _lines.Count > 0;
    }

    private void RemoveLine(object? sender, EventArgs e)
    {
        if (_dgvLines.SelectedRows.Count == 0) return;
        var idx = _dgvLines.SelectedRows[0].Index;
        _lines.RemoveAt(idx);
        _units.Remove(idx);
        RefreshLinesGrid();
    }

    private void RefreshLinesGrid()
    {
        _dgvLines.DataSource = null;
        _dgvLines.DataSource = _lines.Select(l => new
        {
            l.SkuCode,
            l.SkuDesc,
            l.Qty,
            Batch = l.Batch ?? "",
            BBE   = l.BBE.HasValue ? l.BBE.Value.ToString("dd/MM/yyyy") : ""
        }).ToList();
    }

    // ==========================================================
    // Unit management
    // ==========================================================

    private void PopulateLinePicker()
    {
        _cmbLinePicker.Items.Clear();
        for (int i = 0; i < _lines.Count; i++)
        {
            var l = _lines[i];
            _cmbLinePicker.Items.Add(new LineLookup(i, $"Line {i + 1} — {l.SkuCode} ({l.Qty} units)"));
        }
        _cmbLinePicker.DisplayMember = "Display";
        if (_cmbLinePicker.Items.Count > 0)
            _cmbLinePicker.SelectedIndex = 0;
    }

    private void RefreshUnitsGrid()
    {
        if (_cmbLinePicker.SelectedItem is not LineLookup lineEntry) return;
        var lineIdx = lineEntry.Index;

        if (!_units.TryGetValue(lineIdx, out var units))
            units = [];

        _dgvUnits.DataSource = null;
        _dgvUnits.DataSource = units.Select(u => new
        {
            u.Sscc,
            u.Qty,
            Batch = u.Batch ?? "",
            BBE   = u.BBE.HasValue ? u.BBE.Value.ToString("dd/MM/yyyy") : ""
        }).ToList();
    }

    private void AddUnit(object? sender, EventArgs e)
    {
        if (_cmbLinePicker.SelectedItem is not LineLookup lineEntry) return;

        var sscc = _txtSscc.Text.Trim();
        if (string.IsNullOrWhiteSpace(sscc) || sscc.Length < 18)
        { Msg("SSCC must be at least 18 digits."); return; }

        var lineIdx = lineEntry.Index;
        if (!_units.ContainsKey(lineIdx))
            _units[lineIdx] = [];

        var bbe   = _chkUnitBBE.Checked ? (DateTime?)_dtpUnitBBE.Value.Date : null;
        var batch = string.IsNullOrWhiteSpace(_txtUnitBatch.Text) ? null : _txtUnitBatch.Text.Trim();

        _units[lineIdx].Add(new UnitEntry(sscc, (int)_nudUnitQty.Value, batch, bbe));
        RefreshUnitsGrid();

        _txtSscc.Clear();
        _nudUnitQty.Value    = 1;
        _txtUnitBatch.Clear();
        _chkUnitBBE.Checked  = false;
    }

    private void RemoveUnit(object? sender, EventArgs e)
    {
        if (_cmbLinePicker.SelectedItem is not LineLookup lineEntry) return;
        if (_dgvUnits.SelectedRows.Count == 0) return;

        var lineIdx = lineEntry.Index;
        var unitIdx = _dgvUnits.SelectedRows[0].Index;

        if (_units.TryGetValue(lineIdx, out var units) && unitIdx < units.Count)
        {
            units.RemoveAt(unitIdx);
            RefreshUnitsGrid();
        }
    }

    // ==========================================================
    // Finish — create in DB
    // ==========================================================

    private void Finish()
    {
        if (!ValidateStage(_tabs.SelectedIndex)) return;

        var inboundRef   = _txtRef.Text.Trim();
        var supplierCode = (_cmbSupplier.SelectedItem as PartyLookup)?.Code;
        var haulierCode  = (_cmbHaulier.SelectedItem as PartyLookup)?.Code;
        DateTime? eta    = _chkArrivalKnown.Checked ? _dtpArrival.Value : null;

        // 1 — Create header
        var headerResult = _commandRepo.CreateInbound(
            inboundRef:        inboundRef,
            supplierPartyCode: supplierCode!,
            haulierPartyCode:  haulierCode,
            expectedArrivalAt: eta);

        if (!headerResult.Success)
        { Msg($"Could not create inbound: {headerResult.FriendlyMessage}"); return; }

        // 2 — Create lines
        for (int i = 0; i < _lines.Count; i++)
        {
            var line       = _lines[i];
            var lineResult = _commandRepo.AddInboundLine(
                inboundRef:     inboundRef,
                skuCode:        line.SkuCode,
                expectedQty:    line.Qty,
                batchNumber:    line.Batch,
                bestBeforeDate: line.BBE);

            if (!lineResult.Success)
            { Msg($"Line {i + 1} ({line.SkuCode}) failed: {lineResult.FriendlyMessage}"); return; }

            // 3 — Create units for this line (if any)
            if (_units.TryGetValue(i, out var units))
            {
                foreach (var unit in units)
                {
                    var unitResult = _commandRepo.AddExpectedUnit(
                        inboundRef:     inboundRef,
                        sscc:           unit.Sscc,
                        quantity:       unit.Qty,
                        batchNumber:    unit.Batch,
                        bestBeforeDate: unit.BBE);

                    if (!unitResult.Success)
                        Msg($"SSCC {unit.Sscc} skipped: {unitResult.FriendlyMessage}");
                }
            }
        }

        _createdInboundRef = inboundRef;
        DialogResult       = DialogResult.OK;
    }

    // ==========================================================
    // Helpers
    // ==========================================================

    private static TableLayoutPanel MakeTable(int rows)
    {
        var t = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = rows,
            Padding     = new Padding(0, 4, 0, 0)
        };
        for (int i = 0; i < rows; i++)
            t.RowStyles.Add(new RowStyle(SizeType.Absolute, 30f));
        t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140));
        t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        return t;
    }

    private static void AddRow(TableLayoutPanel t, int row, string label, Control ctrl)
    {
        var lbl = new Label
        {
            Text      = label,
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleRight,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f)
        };
        ctrl.Dock = DockStyle.Fill;
        t.Controls.Add(lbl,  0, row);
        t.Controls.Add(ctrl, 1, row);
    }

    private void Msg(string text) =>
        MessageBox.Show(this, text, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);

    // Lookup types
    private record PartyLookup(string? Code, string Display);
    private record SkuLookup(string? Code, string Display);
    private record LineLookup(int Index, string Display);
}
