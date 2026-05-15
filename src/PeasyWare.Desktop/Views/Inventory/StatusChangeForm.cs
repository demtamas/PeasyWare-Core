using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Inventory;

/// <summary>
/// Modal for changing the stock status of one or more selected inventory units.
/// Shows the count of affected units, a status dropdown, and an optional reason.
/// </summary>
public sealed class StatusChangeForm : Form
{
    private readonly ComboBox   _cboStatus = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox    _txtReason = new() { MaxLength     = 200, PlaceholderText = "Optional reason…" };
    private readonly Button     _btnOk     = new() { Text = "Apply",  DialogResult = DialogResult.OK };
    private readonly Button     _btnCancel = new() { Text = "Cancel", DialogResult = DialogResult.Cancel };

    public string  NewStatusCode => ((StatusItem)_cboStatus.SelectedItem!).Code;
    public string? Reason        => string.IsNullOrWhiteSpace(_txtReason.Text) ? null : _txtReason.Text.Trim();

    public StatusChangeForm(int unitCount)
    {
        Text            = "Change Stock Status";
        Size            = new Size(380, 220);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        AcceptButton    = _btnOk;
        CancelButton    = _btnCancel;

        _cboStatus.Items.AddRange(new object[]
        {
            new StatusItem("AV", "AV — Available"),
            new StatusItem("QC", "QC — Quality Hold"),
            new StatusItem("BL", "BL — Blocked"),
            new StatusItem("DM", "DM — Damaged"),
        });
        _cboStatus.SelectedIndex  = 0;
        _cboStatus.DisplayMember  = "Display";

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 4,
            Padding     = new Padding(12),
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        for (int i = 0; i < 4; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 36F));

        // Info row
        var lblInfo = new Label
        {
            Text      = $"Units selected:",
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft
        };
        var lblCount = new Label
        {
            Text      = unitCount.ToString(),
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft,
            Font      = new Font(Font, FontStyle.Bold)
        };
        table.Controls.Add(lblInfo,  0, 0);
        table.Controls.Add(lblCount, 1, 0);

        AddRow(table, "New status *", _cboStatus, 1);
        AddRow(table, "Reason",       _txtReason, 2);

        var btnPanel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            Dock          = DockStyle.Bottom,
            Height        = 40,
            Padding       = new Padding(8, 4, 8, 4)
        };
        _btnOk.Width     = 80;
        _btnCancel.Width = 80;
        btnPanel.Controls.Add(_btnCancel);
        btnPanel.Controls.Add(_btnOk);

        Controls.Add(table);
        Controls.Add(btnPanel);
    }

    private static void AddRow(TableLayoutPanel table, string label, Control control, int row)
    {
        table.Controls.Add(new Label
        {
            Text      = label,
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft
        }, 0, row);
        control.Dock = DockStyle.Fill;
        table.Controls.Add(control, 1, row);
    }

    private sealed record StatusItem(string Code, string Display)
    {
        public override string ToString() => Display;
    }
}
