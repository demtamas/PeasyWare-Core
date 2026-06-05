using PeasyWare.Application.Interfaces;
using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class EditBinForm : Form
{
    private readonly ILocationCommandRepository _commandRepo;
    private readonly ILocationQueryRepository   _queryRepo;

    // Current values (displayed as placeholders / defaults)
    private readonly string _currentBinCode;
    private readonly bool   _hasStock;

    private readonly TextBox       _txtCode     = new();
    private readonly ComboBox      _cmbType     = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox      _cmbZone     = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox      _cmbSection  = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown _nudCapacity = new() { Minimum = 1, Maximum = 9999 };
    private readonly TextBox       _txtNotes    = new();
    private readonly CheckBox      _chkClearNotes = new() { Text = "Clear notes", AutoSize = true };

    public EditBinForm(
        string                      binCode,
        bool                        hasStock,
        string                      currentType,
        string?                     currentZone,
        string?                     currentSection,
        int                         currentCapacity,
        string?                     currentNotes,
        ILocationCommandRepository  commandRepo,
        ILocationQueryRepository    queryRepo)
    {
        _commandRepo    = commandRepo;
        _queryRepo      = queryRepo;
        _currentBinCode = binCode;
        _hasStock       = hasStock;

        Text            = $"Edit Location — {binCode}";
        Size            = new Size(440, 320);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        BuildLayout(currentType, currentZone, currentSection, currentCapacity, currentNotes);
    }

    private void BuildLayout(
        string  currentType,
        string? currentZone,
        string? currentSection,
        int     currentCapacity,
        string? currentNotes)
    {
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 7,
            Padding     = new Padding(12, 12, 12, 0)
        };
        for (int i = 0; i < 7; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 30f));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        // Populate values
        _txtCode.Text    = _currentBinCode;
        _nudCapacity.Value = currentCapacity;
        _txtNotes.Text   = currentNotes ?? "";
        _txtNotes.PlaceholderText = "Optional notes";

        // Type
        _cmbType.Items.Add("(no change)");
        foreach (var t in _queryRepo.GetStorageTypeCodes())
            _cmbType.Items.Add(t);
        _cmbType.SelectedIndex = 0;
        // Select current type
        for (int i = 1; i < _cmbType.Items.Count; i++)
            if (_cmbType.Items[i]?.ToString() == currentType)
            { _cmbType.SelectedIndex = i; break; }

        // Zone
        _cmbZone.Items.Add("(no change)");
        _cmbZone.Items.Add("(none)");
        foreach (var z in _queryRepo.GetZoneCodes())
            _cmbZone.Items.Add(z);
        _cmbZone.SelectedIndex = 0;
        if (currentZone != null)
            for (int i = 2; i < _cmbZone.Items.Count; i++)
                if (_cmbZone.Items[i]?.ToString() == currentZone)
                { _cmbZone.SelectedIndex = i; break; }

        // Section
        _cmbSection.Items.Clear();
        _cmbSection.Items.Add("(no change)");
        _cmbSection.Items.Add("(none)");
        foreach (var s in _queryRepo.GetSectionCodes())
            _cmbSection.Items.Add(s);
        _cmbSection.SelectedIndex = 0;
        if (currentSection != null)
            for (int i = 2; i < _cmbSection.Items.Count; i++)
                if (_cmbSection.Items[i]?.ToString() == currentSection)
                { _cmbSection.SelectedIndex = i; break; }

        // Restrict rename and type change when stock present
        if (_hasStock)
        {
            _txtCode.Enabled = false;
            _txtCode.BackColor = Color.FromArgb(255, 248, 225);
            _cmbType.Enabled = false;
            _cmbType.BackColor = Color.FromArgb(255, 248, 225);
        }

        AddRow(table, 0, "Bin Code",      _txtCode);
        AddRow(table, 1, "Storage Type",  _cmbType);
        AddRow(table, 2, "Zone",          _cmbZone);
        AddRow(table, 3, "Section",       _cmbSection);
        AddRow(table, 4, "Capacity",      _nudCapacity);
        AddRow(table, 5, "Notes",         _txtNotes);
        AddRow(table, 6, "",              _chkClearNotes);

        if (_hasStock)
        {
            var lblWarning = new Label
            {
                Text      = "⚠ Bin code and type cannot be changed while stock is present.",
                Dock      = DockStyle.Bottom,
                Height    = 20,
                ForeColor = Color.DarkOrange,
                Font      = new Font(Font.FontFamily, 8f),
                Padding   = new Padding(12, 0, 0, 2)
            };
            Controls.Add(lblWarning);
        }

        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 46, Padding = new Padding(12, 8, 0, 0) };
        var btnSave   = new Button { Text = "Save",   Width = 80, Height = 28, Location = new Point(12, 8) };
        var btnCancel = new Button { Text = "Cancel", Width = 80, Height = 28, Location = new Point(100, 8), DialogResult = DialogResult.Cancel };
        btnSave.Click += BtnSave_Click;
        pnlFooter.Controls.AddRange([btnSave, btnCancel]);

        Controls.Add(table);
        Controls.Add(pnlFooter);
        CancelButton = btnCancel;
    }

    private void BtnSave_Click(object? sender, EventArgs e)
    {
        var newCode     = _txtCode.Text.Trim().ToUpper();
        var newBinCode  = newCode != _currentBinCode ? newCode : null;
        var typeCode    = _cmbType.SelectedIndex > 0 ? _cmbType.SelectedItem?.ToString() : null;
        var zoneCode    = _cmbZone.SelectedIndex == 1 ? "" :      // "(none)" = clear
                          _cmbZone.SelectedIndex > 1  ? _cmbZone.SelectedItem?.ToString() : null;
        var clearNotes  = _chkClearNotes.Checked;
        var notes       = !clearNotes && !string.IsNullOrWhiteSpace(_txtNotes.Text)
                          ? _txtNotes.Text.Trim() : null;

        var result = _commandRepo.UpdateBin(
            binCode:         _currentBinCode,
            newBinCode:      newBinCode,
            storageTypeCode: typeCode,
            zoneCode:        zoneCode == "" ? null : zoneCode,
            capacity:        (int)_nudCapacity.Value,
            notes:           notes,
            clearNotes:      clearNotes);

        if (!result.Success)
        { MessageBox.Show(this, result.FriendlyMessage, "Cannot Save", MessageBoxButtons.OK, MessageBoxIcon.Warning); return; }

        if (result.FriendlyMessage.Contains("updated", StringComparison.OrdinalIgnoreCase))
        {
            // Capacity warning is embedded in the result data — check if we should surface it
        }

        DialogResult = DialogResult.OK;
    }

    private static void AddRow(TableLayoutPanel t, int row, string label, Control ctrl)
    {
        var lbl = new Label { Text = label, Dock = DockStyle.Fill, TextAlign = System.Drawing.ContentAlignment.MiddleRight, Font = new Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8.5f) };
        ctrl.Dock = DockStyle.Fill;
        t.Controls.Add(lbl, 0, row);
        t.Controls.Add(ctrl, 1, row);
    }
}
