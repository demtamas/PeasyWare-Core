using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Outbound;

public sealed class CreateOrderForm : Form
{
    private readonly IOutboundCommandRepository _commandRepo;
    private readonly ISkuQueryRepository        _skuRepo;
    private readonly IPartyQueryRepository      _partyRepo;

    // ── Header controls ─────────────────────────────────────────────────
    private readonly TextBox        _txtRef        = new();
    private readonly ComboBox       _cmbCustomer   = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox       _cmbHaulier    = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox       _cmbAddress    = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly DateTimePicker _dtpRequired   = new() { Format = DateTimePickerFormat.Short };
    private readonly CheckBox       _chkRequired   = new() { Text = "Set required date", Checked = false };
    private readonly TextBox        _txtNotes      = new();

    // ── Lines controls ───────────────────────────────────────────────────
    private readonly DataGridView   _dgvLines      = new();
    private readonly ComboBox       _cmbLineSku    = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown  _nudQty        = new() { Minimum = 1, Maximum = 999999, Value = 1 };
    private readonly TextBox        _txtBatch      = new();
    private readonly DateTimePicker _dtpBBE        = new() { Format = DateTimePickerFormat.Short };
    private readonly CheckBox       _chkBBE        = new() { Text = "Has BBE", Checked = false };

    // ── Footer ───────────────────────────────────────────────────────────
    private readonly Button _btnCreate = new() { Text = "Create",  Width = 100, Height = 30 };
    private readonly Button _btnCancel = new() { Text = "Cancel",  Width = 100, Height = 30, DialogResult = DialogResult.Cancel };

    public string? CreatedOrderRef { get; private set; }

    private readonly List<LineEntry>       _lines       = [];
    private readonly List<AddressLookup>   _addresses   = [];
    private          List<SkuDto>          _skus        = [];

    private record LineEntry(string SkuCode, string SkuDesc, int Qty, string? Batch, DateTime? BBE);
    private record PartyLookup(string? Code, string Display);
    private record AddressLookup(int? Id, string Display);

    // ==========================================================

    public CreateOrderForm(
        IOutboundCommandRepository commandRepo,
        ISkuQueryRepository        skuRepo,
        IPartyQueryRepository      partyRepo)
    {
        _commandRepo = commandRepo;
        _skuRepo     = skuRepo;
        _partyRepo   = partyRepo;

        Text            = "New Outbound Order";
        Size            = new Size(760, 580);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        AcceptButton    = _btnCreate;
        CancelButton    = _btnCancel;

        BuildLayout();
        LoadLookups();
        SuggestRef();
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
        pnlHeader.Controls.Add(new Label
        {
            Text      = "New Outbound Order",
            Dock      = DockStyle.Fill,
            Font      = new Font(Font.FontFamily, 11f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize  = false
        });

        // Header fields
        var pnlFields = new Panel { Dock = DockStyle.Top, Height = 200, Padding = new Padding(12, 8, 12, 0) };

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 7
        };
        for (int i = 0; i < 7; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 28f));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _chkRequired.CheckedChanged += (_, _) => _dtpRequired.Enabled = _chkRequired.Checked;
        _dtpRequired.Enabled         = false;
        _cmbCustomer.SelectedIndexChanged += (_, _) => OnCustomerChanged();
        _txtNotes.PlaceholderText = "Optional notes";

        AddRow(table, 0, "Order Ref *",      _txtRef);
        AddRow(table, 1, "Customer *",       _cmbCustomer);
        AddRow(table, 2, "Delivery Address", _cmbAddress);
        AddRow(table, 3, "Haulier",          _cmbHaulier);
        AddRow(table, 4, "Required date",    _chkRequired);
        AddRow(table, 5, "Date",             _dtpRequired);
        AddRow(table, 6, "Notes",            _txtNotes);

        pnlFields.Controls.Add(table);

        // Lines section
        var lblLines = new Label
        {
            Text      = "Order lines (at least one required)",
            Dock      = DockStyle.Top,
            Height    = 22,
            Padding   = new Padding(12, 4, 0, 0),
            Font      = new Font(Font.FontFamily, 8.5f, FontStyle.Bold),
            ForeColor = SystemColors.GrayText
        };

        ConfigureLinesGrid(_dgvLines);
        _dgvLines.Dock = DockStyle.Fill;

        // Add line panel
        var pnlAdd = new Panel { Dock = DockStyle.Bottom, Height = 36, Padding = new Padding(12, 4, 12, 0) };

        _cmbLineSku.Width        = 200;
        _cmbLineSku.Location     = new Point(0, 4);
        _cmbLineSku.DisplayMember = "Display";

        _nudQty.Size     = new Size(70, 24);
        _nudQty.Location = new Point(208, 4);

        _txtBatch.Size            = new Size(100, 24);
        _txtBatch.Location        = new Point(286, 4);
        _txtBatch.PlaceholderText = "Batch";

        _chkBBE.AutoSize = true;
        _chkBBE.Location = new Point(394, 6);
        _chkBBE.CheckedChanged += (_, _) => _dtpBBE.Visible = _chkBBE.Checked;

        _dtpBBE.Size     = new Size(100, 24);
        _dtpBBE.Location = new Point(458, 4);
        _dtpBBE.Visible  = false;

        var btnAdd = new Button { Text = "+ Add", Size = new Size(70, 24), Location = new Point(566, 4) };
        btnAdd.Click += AddLine;

        var btnDel = new Button { Text = "Remove", Size = new Size(70, 24), Location = new Point(643, 4) };
        btnDel.Click += RemoveLine;

        pnlAdd.Controls.AddRange([_cmbLineSku, _nudQty, _txtBatch, _chkBBE, _dtpBBE, btnAdd, btnDel]);

        // Footer
        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(12, 10, 12, 0) };
        _btnCreate.Location  = new Point(12, 10);
        _btnCancel.Location  = new Point(120, 10);
        _btnCreate.Click    += BtnCreate_Click;
        pnlFooter.Controls.AddRange([_btnCreate, _btnCancel]);

        Controls.Add(_dgvLines);
        Controls.Add(pnlAdd);
        Controls.Add(lblLines);
        Controls.Add(pnlFields);
        Controls.Add(pnlFooter);
        Controls.Add(pnlHeader);
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

    private static void ConfigureLinesGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns   = false;
        dgv.SelectionMode         = DataGridViewSelectionMode.FullRowSelect;
        dgv.ReadOnly              = true;
        dgv.AllowUserToAddRows    = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;
        dgv.RowHeadersVisible     = false;
        dgv.AutoSizeColumnsMode   = DataGridViewAutoSizeColumnsMode.Fill;
        dgv.BackgroundColor       = SystemColors.Window;
        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor     = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor     = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SKU",         DataPropertyName = "SkuCode",  FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = "SkuDesc",  FillWeight = 22 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Qty",         DataPropertyName = "Qty",      FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Batch",       DataPropertyName = "Batch",    FillWeight = 10 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "BBE",         DataPropertyName = "BBE",      FillWeight = 8  });
    }

    // ==========================================================
    // Lookups
    // ==========================================================

    private void LoadLookups()
    {
        _skus = _skuRepo.GetAll(includeInactive: false).ToList();

        var parties = _partyRepo.GetParties().ToList();

        // Customers
        _cmbCustomer.Items.Add(new PartyLookup(null, "(select customer)"));
        foreach (var p in parties.Where(p => p.IsCustomer))
            _cmbCustomer.Items.Add(new PartyLookup(p.PartyCode, $"{p.DisplayName} ({p.PartyCode})"));
        _cmbCustomer.DisplayMember = "Display";
        _cmbCustomer.SelectedIndex = 0;

        // Hauliers
        _cmbHaulier.Items.Add(new PartyLookup(null, "(none)"));
        foreach (var p in parties.Where(p => p.IsHaulier))
            _cmbHaulier.Items.Add(new PartyLookup(p.PartyCode, $"{p.DisplayName} ({p.PartyCode})"));
        _cmbHaulier.DisplayMember = "Display";
        _cmbHaulier.SelectedIndex = 0;

        // SKU picker
        _cmbLineSku.Items.Add(new SkuLookup(null, "(select SKU)"));
        foreach (var s in _skus)
            _cmbLineSku.Items.Add(new SkuLookup(s.SkuCode, $"{s.SkuCode} – {s.SkuDescription}"));
        _cmbLineSku.DisplayMember = "Display";
        _cmbLineSku.SelectedIndex = 0;
    }

    private void OnCustomerChanged()
    {
        // Delivery addresses — populated per customer from party_addresses
        // For now default to same as customer party; can be extended with party addresses later
        _cmbAddress.Items.Clear();
        _addresses.Clear();
        _cmbAddress.Items.Add(new AddressLookup(null, "(default / same as customer)"));
        _cmbAddress.DisplayMember = "Display";
        _cmbAddress.SelectedIndex = 0;
    }

    private void SuggestRef()
    {
        _txtRef.Text = $"ORD-{DateTime.Today.Year}-";
        _txtRef.SelectionStart = _txtRef.Text.Length;
    }

    // ==========================================================
    // Lines management
    // ==========================================================

    private void AddLine(object? sender, EventArgs e)
    {
        if (_cmbLineSku.SelectedItem is not SkuLookup sku || sku.Code is null)
        { Msg("Please select a SKU."); return; }

        var bbe   = _chkBBE.Checked ? (DateTime?)_dtpBBE.Value.Date : null;
        var batch = string.IsNullOrWhiteSpace(_txtBatch.Text) ? null : _txtBatch.Text.Trim();

        _lines.Add(new LineEntry(sku.Code, sku.Display, (int)_nudQty.Value, batch, bbe));
        RefreshGrid();

        _cmbLineSku.SelectedIndex = 0;
        _nudQty.Value             = 1;
        _txtBatch.Clear();
        _chkBBE.Checked           = false;
    }

    private void RemoveLine(object? sender, EventArgs e)
    {
        if (_dgvLines.SelectedRows.Count == 0) return;
        _lines.RemoveAt(_dgvLines.SelectedRows[0].Index);
        RefreshGrid();
    }

    private void RefreshGrid()
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
    // Create
    // ==========================================================

    private void BtnCreate_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_txtRef.Text))
        { Msg("Order reference is required."); return; }

        if (_cmbCustomer.SelectedItem is not PartyLookup cust || cust.Code is null)
        { Msg("Please select a customer."); return; }

        if (_lines.Count == 0)
        { Msg("At least one order line is required."); return; }

        var haulierCode  = (_cmbHaulier.SelectedItem as PartyLookup)?.Code;
        var requiredDate = _chkRequired.Checked ? (DateTime?)_dtpRequired.Value.Date : null;
        var notes        = string.IsNullOrWhiteSpace(_txtNotes.Text) ? null : _txtNotes.Text.Trim();

        var lines = _lines.Select(l => new OrderLineDto
        {
            SkuCode        = l.SkuCode,
            OrderedQty     = l.Qty,
            RequestedBatch = l.Batch,
            RequestedBbe   = l.BBE
        }).ToList();

        var result = _commandRepo.CreateOrder(
            orderRef:          _txtRef.Text.Trim(),
            customerPartyCode: cust.Code,
            haulierPartyCode:  haulierCode,
            requiredDate:      requiredDate,
            notes:             notes,
            lines:             lines);

        if (!result.Success)
        { Msg($"Could not create order: {result.FriendlyMessage}"); return; }

        CreatedOrderRef = _txtRef.Text.Trim();
        DialogResult    = DialogResult.OK;
    }

    private void Msg(string text) =>
        MessageBox.Show(this, text, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);

    private record SkuLookup(string? Code, string Display);
}
