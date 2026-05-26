using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Shipments;

public sealed class CreateShipmentForm : Form
{
    private readonly IOutboundCommandRepository _commandRepo;
    private readonly IOutboundQueryRepository   _queryRepo;
    private readonly IPartyQueryRepository      _partyRepo;

    // Header controls
    private readonly TextBox        _txtRef        = new();
    private readonly ComboBox       _cmbHaulier    = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox        _txtVehicle    = new();
    private readonly DateTimePicker _dtpDeparture  = new() { Format = DateTimePickerFormat.Custom, CustomFormat = "dd/MM/yyyy HH:mm", ShowUpDown = false };
    private readonly CheckBox       _chkDeparture  = new() { Text = "Set planned departure", Checked = false };

    // Orders
    private readonly DataGridView   _dgvOrders     = new();

    // Footer
    private readonly Button _btnCreate = new() { Text = "Create",  Width = 100, Height = 30 };
    private readonly Button _btnCancel = new() { Text = "Cancel",  Width = 100, Height = 30, DialogResult = DialogResult.Cancel };

    public string? CreatedShipmentRef { get; private set; }

    private record PartyLookup(string Code, string Display);

    public CreateShipmentForm(
        IOutboundCommandRepository commandRepo,
        IOutboundQueryRepository   queryRepo,
        IPartyQueryRepository      partyRepo)
    {
        _commandRepo = commandRepo;
        _queryRepo   = queryRepo;
        _partyRepo   = partyRepo;

        Text            = "New Shipment";
        Size            = new Size(760, 540);
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
            Text      = "New Shipment",
            Dock      = DockStyle.Fill,
            Font      = new Font(Font.FontFamily, 11f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize  = false
        });

        // Header fields
        var pnlFields = new Panel { Dock = DockStyle.Top, Height = 150, Padding = new Padding(12, 8, 12, 0) };

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 5
        };
        for (int i = 0; i < 5; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 28f));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _chkDeparture.CheckedChanged += (_, _) => _dtpDeparture.Enabled = _chkDeparture.Checked;
        _dtpDeparture.Value   = DateTime.Today.AddHours(8);
        _dtpDeparture.Enabled = false;

        AddRow(table, 0, "Shipment Ref *",   _txtRef);
        AddRow(table, 1, "Haulier *",        _cmbHaulier);
        AddRow(table, 2, "Vehicle Reg",      _txtVehicle);
        AddRow(table, 3, "Plan departure",   _chkDeparture);
        AddRow(table, 4, "Departure",        _dtpDeparture);

        pnlFields.Controls.Add(table);

        // Orders section
        var lblOrders = new Label
        {
            Text      = "Add orders to shipment (optional — can be added later)",
            Dock      = DockStyle.Top,
            Height    = 22,
            Padding   = new Padding(12, 4, 0, 0),
            Font      = new Font(Font.FontFamily, 8.5f, FontStyle.Bold),
            ForeColor = SystemColors.GrayText
        };

        ConfigureOrdersGrid(_dgvOrders);
        _dgvOrders.Dock = DockStyle.Fill;

        // Footer
        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(12, 10, 12, 0) };
        _btnCreate.Location  = new Point(12, 10);
        _btnCancel.Location  = new Point(120, 10);
        _btnCreate.Click    += BtnCreate_Click;
        pnlFooter.Controls.AddRange([_btnCreate, _btnCancel]);

        Controls.Add(_dgvOrders);
        Controls.Add(lblOrders);
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

    private static void ConfigureOrdersGrid(DataGridView dgv)
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
        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor     = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor     = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Order Ref",  DataPropertyName = nameof(OutboundOrderSummaryDto.OrderRef),      FillWeight = 10 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Customer",   DataPropertyName = nameof(OutboundOrderSummaryDto.CustomerName),   FillWeight = 16 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Status",     DataPropertyName = nameof(OutboundOrderSummaryDto.OrderStatusCode), FillWeight = 8 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Required",   DataPropertyName = nameof(OutboundOrderSummaryDto.RequiredDate),   FillWeight = 8 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Ordered",    DataPropertyName = nameof(OutboundOrderSummaryDto.TotalOrdered),   FillWeight = 6 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Allocated",  DataPropertyName = nameof(OutboundOrderSummaryDto.TotalAllocated), FillWeight = 6 });
    }

    // ==========================================================
    // Lookups
    // ==========================================================

    private void LoadLookups()
    {
        // Hauliers
        _cmbHaulier.Items.Add(new PartyLookup("", "(select haulier)"));
        foreach (var p in _partyRepo.GetParties(roleFilter: "HAULIER"))
            _cmbHaulier.Items.Add(new PartyLookup(p.PartyCode, $"{p.DisplayName} ({p.PartyCode})"));
        _cmbHaulier.DisplayMember = "Display";
        _cmbHaulier.SelectedIndex = 0;

        // Orders eligible for shipment (PICKED status, not yet on a shipment)
        var orders = _queryRepo.GetOrdersEligibleForShipment();
        _dgvOrders.DataSource = orders.ToList();
    }

    private void SuggestRef()
    {
        _txtRef.Text = $"SHIP-{DateTime.Today.Year}-";
        _txtRef.SelectionStart = _txtRef.Text.Length;
    }

    // ==========================================================
    // Create
    // ==========================================================

    private void BtnCreate_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_txtRef.Text))
        { Msg("Shipment reference is required."); return; }

        if (_cmbHaulier.SelectedItem is not PartyLookup haulier || string.IsNullOrEmpty(haulier.Code))
        { Msg("Please select a haulier."); return; }

        var vehicleRef = string.IsNullOrWhiteSpace(_txtVehicle.Text) ? null : _txtVehicle.Text.Trim();
        var departure  = _chkDeparture.Checked ? (DateTime?)_dtpDeparture.Value : null;

        // Create shipment header
        var result = _commandRepo.CreateShipment(
            shipmentRef:       _txtRef.Text.Trim(),
            haulierPartyCode:  haulier.Code,
            vehicleRef:        vehicleRef,
            plannedDeparture:  departure);

        if (!result.Success)
        { Msg($"Could not create shipment: {result.FriendlyMessage}"); return; }

        var shipmentRef = _txtRef.Text.Trim();

        // Add selected orders
        foreach (DataGridViewRow row in _dgvOrders.SelectedRows)
        {
            if (row.DataBoundItem is not OutboundOrderSummaryDto order) continue;
            var addResult = _commandRepo.AddOrderToShipment(shipmentRef, order.OrderRef);
            if (!addResult.Success)
                Msg($"Order {order.OrderRef} could not be added: {addResult.FriendlyMessage}");
        }

        CreatedShipmentRef = shipmentRef;
        DialogResult       = DialogResult.OK;
    }

    private void Msg(string text) =>
        MessageBox.Show(this, text, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
}
