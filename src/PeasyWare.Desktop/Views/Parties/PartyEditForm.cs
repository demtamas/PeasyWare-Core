using PeasyWare.Application.Dto;
using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Parties;

public sealed class PartyEditForm : Form
{
    private readonly bool _isEdit;

    // Outputs
    public string  PartyCode    => _txtCode.Text.Trim().ToUpperInvariant();
    public string  LegalName    => _txtLegal.Text.Trim();
    public string  DisplayName  => _txtDisplay.Text.Trim();
    public string? CountryCode  => string.IsNullOrWhiteSpace(_txtCountry.Text) ? null : _txtCountry.Text.Trim().ToUpperInvariant();
    public string? TaxId        => string.IsNullOrWhiteSpace(_txtTaxId.Text)   ? null : _txtTaxId.Text.Trim();
    public bool    IsActive     => _chkActive.Checked;
    public string? Roles
    {
        get
        {
            var selected = _clbRoles.CheckedItems
                .Cast<string>()
                .ToList();
            return selected.Count > 0 ? string.Join(",", selected) : null;
        }
    }

    // Controls
    private readonly TextBox   _txtCode    = new();
    private readonly TextBox   _txtDisplay = new();
    private readonly TextBox   _txtLegal   = new();
    private readonly TextBox   _txtCountry = new();
    private readonly TextBox   _txtTaxId   = new();
    private readonly CheckBox  _chkActive  = new() { Text = "Active", Checked = true };
    private readonly CheckedListBox _clbRoles = new()
    {
        CheckOnClick    = true,
        SelectionMode   = SelectionMode.One,
        BorderStyle     = BorderStyle.FixedSingle
    };
    private readonly Button    _btnSave   = new() { Text = "&Save",   Width = 100, Height = 30 };
    private readonly Button    _btnCancel = new() { Text = "&Cancel", Width = 100, Height = 30, DialogResult = DialogResult.Cancel };

    public PartyEditForm(PartyDto? dto)
    {
        _isEdit = dto is not null;
        Text    = _isEdit ? $"Edit Party — {dto!.PartyCode}" : "New Party";

        BuildLayout();

        if (dto is not null)
            Populate(dto);
    }

    private void BuildLayout()
    {
        Size            = new Size(540, 510);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        AcceptButton    = _btnSave;
        CancelButton    = _btnCancel;

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
            Text      = _isEdit ? "Edit Party" : "New Party",
            Dock      = DockStyle.Fill,
            Font      = new Font(Font.FontFamily, 11f, FontStyle.Bold),
            ForeColor = Color.White,
            AutoSize  = false
        };
        pnlHeader.Controls.Add(lblTitle);

        // Body
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 10,
            Padding     = new Padding(14, 10, 14, 0)
        };
        for (int i = 0; i < 10; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, i == 5 ? 108f : 30f));  // 5 items * ~20px + padding
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        _txtCode.CharacterCasing = CharacterCasing.Upper;
        _txtCountry.MaxLength    = 2;
        _txtCountry.Width        = 60;

        int row = 0;
        AddRow(table, row++, "Party Code *",    _txtCode);
        AddRow(table, row++, "Display Name *",  _txtDisplay);
        AddRow(table, row++, "Legal Name *",    _txtLegal);
        AddRow(table, row++, "Country (ISO2)",  _txtCountry);
        AddRow(table, row++, "Tax / VAT ID",    _txtTaxId);

        // Roles — CheckedListBox, DPI-safe, no clipping
        _clbRoles.Items.AddRange(["SUPPLIER", "CUSTOMER", "HAULIER", "OWNER", "WAREHOUSE"]);
        _clbRoles.Height = 5 * 16 + 4;  // just tall enough for all 5 items
        _clbRoles.Dock   = DockStyle.Fill;

        AddRow(table, row++, "Roles", _clbRoles);
        AddRow(table, row++, "",                 _chkActive);

        // Footer
        var pnlFooter = new Panel
        {
            Dock    = DockStyle.Bottom,
            Height  = 50,
            Padding = new Padding(14, 10, 14, 0)
        };
        _btnSave.Location   = new Point(14, 10);
        _btnCancel.Location = new Point(120 + 14, 10);
        _btnSave.Click     += BtnSave_Click;
        pnlFooter.Controls.Add(_btnSave);
        pnlFooter.Controls.Add(_btnCancel);

        if (_isEdit) _txtCode.ReadOnly = true;

        Controls.Add(table);
        Controls.Add(pnlFooter);
        Controls.Add(pnlHeader);
    }

    private static void AddRow(TableLayoutPanel table, int row, string label, Control control)
    {
        var lbl = new Label
        {
            Text      = label,
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleRight,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f)
        };
        control.Dock = DockStyle.Fill;
        table.Controls.Add(lbl,     0, row);
        table.Controls.Add(control, 1, row);
    }

    private void Populate(PartyDto dto)
    {
        _txtCode.Text    = dto.PartyCode;
        _txtDisplay.Text = dto.DisplayName;
        _txtLegal.Text   = dto.LegalName;
        _txtCountry.Text = dto.CountryCode ?? "";
        _txtTaxId.Text   = dto.TaxId ?? "";
        _chkActive.Checked = dto.IsActive;

        var active = new Dictionary<string, bool>
        {
            ["SUPPLIER"]  = dto.IsSupplier,
            ["CUSTOMER"]  = dto.IsCustomer,
            ["HAULIER"]   = dto.IsHaulier,
            ["OWNER"]     = dto.IsOwner,
            ["WAREHOUSE"] = dto.IsWarehouse
        };
        for (int i = 0; i < _clbRoles.Items.Count; i++)
        {
            var key = _clbRoles.Items[i]?.ToString() ?? "";
            _clbRoles.SetItemChecked(i, active.GetValueOrDefault(key));
        }
    }

    private void BtnSave_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_txtCode.Text))
        { MessageBox.Show(this, "Party code is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

        if (string.IsNullOrWhiteSpace(_txtDisplay.Text))
        { MessageBox.Show(this, "Display name is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

        if (string.IsNullOrWhiteSpace(_txtLegal.Text))
        { MessageBox.Show(this, "Legal name is required.", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

        if (!string.IsNullOrWhiteSpace(_txtCountry.Text) && _txtCountry.Text.Trim().Length != 2)
        { MessageBox.Show(this, "Country code must be 2 characters (ISO 3166-1).", "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

        DialogResult = DialogResult.OK;
    }
}
