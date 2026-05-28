using PeasyWare.Application.Interfaces;
using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class CreateBinForm : Form
{
    private readonly ILocationCommandRepository _commandRepo;
    private readonly ILocationQueryRepository   _queryRepo;

    private readonly TextBox       _txtCode    = new();
    private readonly ComboBox      _cmbType    = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox      _cmbZone    = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown _nudCapacity = new() { Minimum = 1, Maximum = 999, Value = 1 };
    private readonly TextBox       _txtNotes   = new() { PlaceholderText = "Optional notes" };

    public CreateBinForm(ILocationCommandRepository commandRepo, ILocationQueryRepository queryRepo)
    {
        _commandRepo = commandRepo;
        _queryRepo   = queryRepo;

        Text            = "New Location";
        Size            = new Size(400, 280);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        BuildLayout();
        LoadLookups();
    }

    private void BuildLayout()
    {
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 6,
            Padding     = new Padding(12, 12, 12, 0)
        };
        for (int i = 0; i < 6; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 30f));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        AddRow(table, 0, "Bin Code *",     _txtCode);
        AddRow(table, 1, "Storage Type *", _cmbType);
        AddRow(table, 2, "Zone",           _cmbZone);
        AddRow(table, 3, "Capacity",       _nudCapacity);
        AddRow(table, 4, "Notes",          _txtNotes);

        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 46, Padding = new Padding(12, 8, 0, 0) };
        var btnCreate = new Button { Text = "Create",  Width = 90, Height = 28, Location = new Point(12, 8) };
        var btnCancel = new Button { Text = "Cancel",  Width = 80, Height = 28, Location = new Point(110, 8), DialogResult = DialogResult.Cancel };
        btnCreate.Click += BtnCreate_Click;
        pnlFooter.Controls.AddRange([btnCreate, btnCancel]);

        Controls.Add(table);
        Controls.Add(pnlFooter);
        CancelButton = btnCancel;
    }

    private void LoadLookups()
    {
        _cmbType.Items.Clear();
        _cmbType.Items.Add("(select type)");
        foreach (var t in _queryRepo.GetStorageTypeCodes())
            _cmbType.Items.Add(t);
        _cmbType.SelectedIndex = 0;

        _cmbZone.Items.Clear();
        _cmbZone.Items.Add("(none)");
        foreach (var z in _queryRepo.GetZoneCodes())
            _cmbZone.Items.Add(z);
        _cmbZone.SelectedIndex = 0;
    }

    private void BtnCreate_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_txtCode.Text))
        { Msg("Bin code is required."); return; }

        if (_cmbType.SelectedIndex == 0)
        { Msg("Please select a storage type."); return; }

        var zone = _cmbZone.SelectedIndex > 0 ? _cmbZone.SelectedItem?.ToString() : null;

        var result = _commandRepo.CreateBin(
            binCode:         _txtCode.Text.Trim().ToUpper(),
            storageTypeCode: _cmbType.SelectedItem!.ToString()!,
            zoneCode:        zone,
            capacity:        (int)_nudCapacity.Value,
            notes:           string.IsNullOrWhiteSpace(_txtNotes.Text) ? null : _txtNotes.Text.Trim());

        if (!result.Success)
        { Msg(result.FriendlyMessage); return; }

        DialogResult = DialogResult.OK;
    }

    private static void AddRow(TableLayoutPanel t, int row, string label, Control ctrl)
    {
        var lbl = new Label { Text = label, Dock = DockStyle.Fill, TextAlign = System.Drawing.ContentAlignment.MiddleRight, Font = new Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8.5f) };
        ctrl.Dock = DockStyle.Fill;
        t.Controls.Add(lbl, 0, row);
        t.Controls.Add(ctrl, 1, row);
    }

    private void Msg(string text) =>
        MessageBox.Show(this, text, "Validation", MessageBoxButtons.OK, MessageBoxIcon.Warning);
}
