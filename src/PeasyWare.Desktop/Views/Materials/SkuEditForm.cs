using PeasyWare.Application.Dto;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Materials;

/// <summary>
/// Modal form for creating or editing a SKU.
/// Pass null for dto to create a new SKU, or an existing SkuDto to edit.
/// storageTypes and sections are loaded by the caller from the DB.
/// </summary>
public sealed class SkuEditForm : Form
{
    // ── Inputs ────────────────────────────────────────────────────────────
    private readonly TextBox       _txtSkuCode      = new() { MaxLength = 50 };
    private readonly TextBox       _txtDescription  = new() { MaxLength = 200 };
    private readonly TextBox       _txtEan          = new() { MaxLength = 50 };
    private readonly ComboBox      _cboUom          = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox       _txtWeight       = new();
    private readonly NumericUpDown _nudHuQty        = new() { Minimum = 0, Maximum = 9999 };
    private readonly ComboBox      _cboStorageType  = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox      _cboSection      = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly CheckBox      _chkBatchReq     = new() { Text = "Batch number required" };
    private readonly CheckBox      _chkFullHuReq    = new() { Text = "Full HU required" };
    private readonly CheckBox      _chkHazardous    = new() { Text = "Hazardous" };
    private readonly CheckBox      _chkActive       = new() { Text = "Active", Checked = true };

    private readonly Button _btnSave   = new() { Text = "Save",   DialogResult = DialogResult.OK };
    private readonly Button _btnCancel = new() { Text = "Cancel", DialogResult = DialogResult.Cancel };

    // ── Public results ────────────────────────────────────────────────────
    public string   SkuCode            => _txtSkuCode.Text.Trim().ToUpperInvariant();
    public string   SkuDescription     => _txtDescription.Text.Trim();
    public string?  Ean                => string.IsNullOrWhiteSpace(_txtEan.Text)   ? null : _txtEan.Text.Trim();
    public string   UomCode            => _cboUom.SelectedItem?.ToString()          ?? "Each";
    public decimal? WeightPerUnit      => decimal.TryParse(_txtWeight.Text, out var w) ? w : null;
    public int      StandardHuQuantity => (int)_nudHuQty.Value;
    public string?  PreferredStorageTypeCode => (_cboStorageType.SelectedItem as StorageLookup)?.Code;
    public string?  PreferredSectionCode     => (_cboSection.SelectedItem as StorageLookup)?.Code;
    public bool     IsBatchRequired    => _chkBatchReq.Checked;
    public bool     IsFullHuRequired   => _chkFullHuReq.Checked;
    public bool     IsHazardous        => _chkHazardous.Checked;
    public bool     IsActive           => _chkActive.Checked;

    private readonly bool _isEdit;

    public SkuEditForm(
        SkuDto? dto,
        IReadOnlyList<StorageLookup> storageTypes,
        IReadOnlyList<StorageLookup> sections)
    {
        _isEdit = dto is not null && !string.IsNullOrEmpty(dto.SkuCode);
        Text    = _isEdit ? $"Edit SKU — {dto!.SkuCode}" : "New SKU";

        BuildLayout(storageTypes, sections);
        WireValidation();

        if (dto is not null)
            Populate(dto);
    }

    private void BuildLayout(
        IReadOnlyList<StorageLookup> storageTypes,
        IReadOnlyList<StorageLookup> sections)
    {
        Size            = new Size(500, 540);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        AcceptButton    = _btnSave;
        CancelButton    = _btnCancel;

        _cboUom.Items.AddRange(new object[] { "Each", "Case", "Pallet", "KG", "L" });
        _cboUom.SelectedIndex = 0;

        // Storage type dropdown — blank = no preference
        _cboStorageType.Items.Add(new StorageLookup(null, "(No preference)"));
        foreach (var st in storageTypes)
            _cboStorageType.Items.Add(st);
        _cboStorageType.SelectedIndex = 0;
        _cboStorageType.DisplayMember = "Display";

        // Section dropdown — blank = no preference
        _cboSection.Items.Add(new StorageLookup(null, "(No preference)"));
        foreach (var s in sections)
            _cboSection.Items.Add(s);
        _cboSection.SelectedIndex = 0;
        _cboSection.DisplayMember = "Display";

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 13,
            Padding     = new Padding(12),
            AutoSize    = false
        };

        for (int i = 0; i < 13; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 30F));

        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 170));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        int row = 0;
        AddRow(table, row++, "SKU Code *",          _txtSkuCode);
        AddRow(table, row++, "Description *",        _txtDescription);
        AddRow(table, row++, "EAN / Barcode",        _txtEan);
        AddRow(table, row++, "Unit of Measure",      _cboUom);
        AddRow(table, row++, "Weight (kg)",          _txtWeight);
        AddRow(table, row++, "HU Quantity",          _nudHuQty);
        AddRow(table, row++, "Preferred Storage",    _cboStorageType);
        AddRow(table, row++, "Preferred Section",    _cboSection);

        // Checkboxes — span both columns for full width, fixed height
        _chkBatchReq.AutoSize  = false;
        _chkFullHuReq.AutoSize = false;
        _chkHazardous.AutoSize = false;
        _chkActive.AutoSize    = false;
        _chkBatchReq.Height    = 24;
        _chkFullHuReq.Height   = 24;
        _chkHazardous.Height   = 24;
        _chkActive.Height      = 24;
        _chkBatchReq.Dock      = DockStyle.Fill;
        _chkFullHuReq.Dock     = DockStyle.Fill;
        _chkHazardous.Dock     = DockStyle.Fill;
        _chkActive.Dock        = DockStyle.Fill;

        table.SetColumnSpan(_chkBatchReq,  2);
        table.SetColumnSpan(_chkFullHuReq, 2);
        table.SetColumnSpan(_chkHazardous, 2);
        table.SetColumnSpan(_chkActive,    2);

        table.Controls.Add(_chkBatchReq,  0, row++);
        table.Controls.Add(_chkFullHuReq, 0, row++);
        table.Controls.Add(_chkHazardous, 0, row++);
        table.Controls.Add(_chkActive,    0, row++);

        var btnPanel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            Dock          = DockStyle.Bottom,
            Height        = 40,
            Padding       = new Padding(8, 4, 8, 4)
        };

        _btnSave.Width   = 80;
        _btnCancel.Width = 80;

        btnPanel.Controls.Add(_btnCancel);
        btnPanel.Controls.Add(_btnSave);

        Controls.Add(table);
        Controls.Add(btnPanel);

        if (_isEdit)
        {
            _txtSkuCode.ReadOnly  = true;
            _txtSkuCode.BackColor = SystemColors.Control;
        }
    }

    private static void AddRow(TableLayoutPanel table, int row, string label, Control control)
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

    private void WireValidation()
    {
        _btnSave.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(_txtSkuCode.Text))
            {
                Show("SKU Code is required.");
                return;
            }
            if (string.IsNullOrWhiteSpace(_txtDescription.Text))
            {
                Show("Description is required.");
                return;
            }
            if (!string.IsNullOrWhiteSpace(_txtWeight.Text) &&
                !decimal.TryParse(_txtWeight.Text, out _))
            {
                Show("Weight must be a valid decimal number.");
                return;
            }
        };

        void Show(string msg)
        {
            MessageBox.Show(msg, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            DialogResult = DialogResult.None;
        }
    }

    private void Populate(SkuDto dto)
    {
        _txtSkuCode.Text     = dto.SkuCode;
        _txtDescription.Text = dto.SkuDescription;
        _txtEan.Text         = dto.Ean ?? "";
        _nudHuQty.Value      = dto.StandardHuQuantity;
        _txtWeight.Text      = dto.WeightPerUnit?.ToString("F3") ?? "";
        _chkBatchReq.Checked  = dto.IsBatchRequired;
        _chkFullHuReq.Checked = dto.IsFullHuRequired;
        _chkHazardous.Checked = dto.IsHazardous;
        _chkActive.Checked   = dto.IsActive;

        var uomIdx = _cboUom.Items.IndexOf(dto.UomCode);
        _cboUom.SelectedIndex = uomIdx >= 0 ? uomIdx : 0;

        SelectLookup(_cboStorageType, dto.PreferredStorageTypeCode);
        SelectLookup(_cboSection,     dto.PreferredSectionCode);
    }

    private static void SelectLookup(ComboBox cbo, string? code)
    {
        if (code is null) { cbo.SelectedIndex = 0; return; }
        for (int i = 0; i < cbo.Items.Count; i++)
        {
            if (cbo.Items[i] is StorageLookup l && l.Code == code)
            { cbo.SelectedIndex = i; return; }
        }
        cbo.SelectedIndex = 0;
    }
}

/// <summary>Simple lookup item for storage type / section dropdowns.</summary>
public sealed record StorageLookup(string? Code, string Display)
{
    public override string ToString() => Display;
}
