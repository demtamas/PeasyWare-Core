using PeasyWare.Application.Dto;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Materials;

public sealed class CustomerShelfLifeEditForm : Form
{
    private readonly ComboBox _cboCustomer = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _cboSku      = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown _nudDays = new() { Minimum = 0, Maximum = 9999 };

    private readonly Button _btnSave   = new() { Text = "Save",   DialogResult = DialogResult.OK };
    private readonly Button _btnCancel = new() { Text = "Cancel", DialogResult = DialogResult.Cancel };

    public string CustomerPartyCode => ((LookupItem)_cboCustomer.SelectedItem!).Code;
    public string SkuCode           => ((LookupItem)_cboSku.SelectedItem!).Code;
    public int    MinimumRemainingShelfLifeDays => (int)_nudDays.Value;

    private sealed record LookupItem(string Code, string Display)
    {
        public override string ToString() => Display;
    }

    public CustomerShelfLifeEditForm(
        IReadOnlyList<PartyDto> customers,
        IReadOnlyList<SkuDto>   skus,
        CustomerShelfLifeRequirementDto? existing = null)
    {
        Text            = existing is null ? "Add shelf-life requirement" : "Edit shelf-life requirement";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition   = FormStartPosition.CenterParent;
        MaximizeBox     = false;
        MinimizeBox     = false;
        Size            = new Size(420, 220);

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            Padding     = new Padding(16),
            ColumnCount = 2,
            RowCount    = 4
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 140F));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        for (int i = 0; i < 4; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 34F));

        _cboCustomer.Dock = DockStyle.Fill;
        _cboCustomer.Items.AddRange(customers.Select(c => new LookupItem(c.PartyCode, $"{c.DisplayName} ({c.PartyCode})")).ToArray());

        _cboSku.Dock = DockStyle.Fill;
        _cboSku.Items.AddRange(skus.Select(s => new LookupItem(s.SkuCode, $"{s.SkuCode} — {s.SkuDescription}")).ToArray());

        _nudDays.Dock = DockStyle.Fill;

        int row = 0;
        AddRow(table, row++, "Customer",             _cboCustomer);
        AddRow(table, row++, "SKU",                   _cboSku);
        AddRow(table, row++, "Min shelf life (days)", _nudDays);

        if (existing is not null)
        {
            // Composite key (customer + SKU) - "editing" only ever changes
            // the days value. Changing either dropdown would really be
            // creating a different requirement, not editing this one, so
            // both are locked and pre-selected rather than left open.
            _cboCustomer.SelectedItem = _cboCustomer.Items.Cast<LookupItem>()
                .FirstOrDefault(i => i.Code == existing.CustomerPartyCode);
            _cboSku.SelectedItem = _cboSku.Items.Cast<LookupItem>()
                .FirstOrDefault(i => i.Code == existing.SkuCode);
            _cboCustomer.Enabled = false;
            _cboSku.Enabled      = false;
            _nudDays.Value       = existing.MinimumRemainingShelfLifeDays;
        }

        var buttonPanel = new FlowLayoutPanel
        {
            Dock          = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            Height        = 44,
            Padding       = new Padding(8)
        };
        buttonPanel.Controls.Add(_btnCancel);
        buttonPanel.Controls.Add(_btnSave);

        Controls.Add(table);
        Controls.Add(buttonPanel);

        AcceptButton = _btnSave;
        CancelButton = _btnCancel;

        _btnSave.Click += (_, _) =>
        {
            if (_cboCustomer.SelectedItem is null || _cboSku.SelectedItem is null)
            {
                MessageBox.Show(this, "Please select both a customer and a SKU.",
                    "Shelf life requirement", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
            }
        };
    }

    private static void AddRow(TableLayoutPanel table, int row, string label, Control control)
    {
        table.Controls.Add(new Label { Text = label, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, row);
        table.Controls.Add(control, 1, row);
    }
}
