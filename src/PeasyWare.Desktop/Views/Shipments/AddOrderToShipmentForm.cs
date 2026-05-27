using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Shipments;

public sealed class AddOrderToShipmentForm : Form
{
    private readonly string                      _shipmentRef;
    private readonly IOutboundQueryRepository    _queryRepo;
    private readonly IOutboundCommandRepository  _commandRepo;

    private readonly DataGridView _dgvOrders = new();
    private readonly Button _btnAdd    = new() { Text = "Add selected",  Width = 110, Height = 30, Enabled = false };
    private readonly Button _btnCancel = new() { Text = "Cancel",        Width = 100, Height = 30, DialogResult = DialogResult.Cancel };

    public AddOrderToShipmentForm(
        string                     shipmentRef,
        IOutboundQueryRepository   queryRepo,
        IOutboundCommandRepository commandRepo)
    {
        _shipmentRef = shipmentRef;
        _queryRepo   = queryRepo;
        _commandRepo = commandRepo;

        Text            = $"Add Order — {shipmentRef}";
        Size            = new Size(760, 420);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        CancelButton    = _btnCancel;

        BuildLayout();
        LoadOrders();
    }

    private void BuildLayout()
    {
        var pnlHeader = new Panel
        {
            Dock      = DockStyle.Top,
            Height    = 44,
            BackColor = Color.FromArgb(45, 45, 48),
            Padding   = new Padding(14, 10, 0, 0)
        };
        pnlHeader.Controls.Add(new Label
        {
            Text      = $"Select an order to add to {_shipmentRef}",
            Dock      = DockStyle.Fill,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize  = false
        });

        ConfigureGrid(_dgvOrders);
        _dgvOrders.Dock              = DockStyle.Fill;
        _dgvOrders.SelectionChanged += (_, _) => _btnAdd.Enabled = _dgvOrders.SelectedRows.Count == 1;

        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(12, 10, 12, 0) };
        _btnAdd.Location    = new Point(12, 10);
        _btnCancel.Location = new Point(130, 10);
        _btnAdd.Click      += BtnAdd_Click;
        pnlFooter.Controls.AddRange([_btnAdd, _btnCancel]);

        Controls.Add(_dgvOrders);
        Controls.Add(pnlFooter);
        Controls.Add(pnlHeader);
    }

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
        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor     = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor     = Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Order Ref",  DataPropertyName = nameof(OutboundOrderSummaryDto.OrderRef),       FillWeight = 10 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Customer",   DataPropertyName = nameof(OutboundOrderSummaryDto.CustomerName),    FillWeight = 16 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Status",     DataPropertyName = nameof(OutboundOrderSummaryDto.OrderStatusCode),  FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Required",   DataPropertyName = nameof(OutboundOrderSummaryDto.RequiredDate),    FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Ordered",    DataPropertyName = nameof(OutboundOrderSummaryDto.TotalOrdered),    FillWeight = 6  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Allocated",  DataPropertyName = nameof(OutboundOrderSummaryDto.TotalAllocated),  FillWeight = 6  });
    }

    private void LoadOrders()
    {
        var orders = _queryRepo.GetOrdersEligibleForShipment().ToList();
        _dgvOrders.DataSource = orders;

        if (orders.Count == 0)
        {
            MessageBox.Show(this,
                "No eligible orders found.\n\nOrders must be in NEW, ALLOCATED, PICKING, or PICKED status and not already on an active shipment.",
                "No Orders Available",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
    }

    private void BtnAdd_Click(object? sender, EventArgs e)
    {
        if (_dgvOrders.SelectedRows.Count == 0) return;
        if (_dgvOrders.SelectedRows[0].DataBoundItem is not OutboundOrderSummaryDto order) return;

        var result = _commandRepo.AddOrderToShipment(_shipmentRef, order.OrderRef);

        if (!result.Success)
        {
            MessageBox.Show(this, result.FriendlyMessage, "Cannot Add Order",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        DialogResult = DialogResult.OK;
    }
}
