using PeasyWare.Application.Interfaces;
using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class CreateBinsBulkForm : Form
{
    private readonly ILocationCommandRepository _commandRepo;
    private readonly ILocationQueryRepository   _queryRepo;

    private readonly TextBox       _txtPrefix   = new() { PlaceholderText = "e.g. R" };
    private readonly ComboBox      _cmbType     = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox      _cmbZone     = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly NumericUpDown _nudRowFrom  = new() { Minimum = 1,  Maximum = 99, Value = 1 };
    private readonly NumericUpDown _nudRowTo    = new() { Minimum = 1,  Maximum = 99, Value = 10 };
    private readonly TextBox       _txtColFrom  = new() { Text = "A",   MaxLength = 1, Width = 40 };
    private readonly TextBox       _txtColTo    = new() { Text = "D",   MaxLength = 1, Width = 40 };
    private readonly NumericUpDown _nudDepthFrom = new() { Minimum = 1, Maximum = 9,  Value = 1 };
    private readonly NumericUpDown _nudDepthTo   = new() { Minimum = 1, Maximum = 9,  Value = 1 };
    private readonly NumericUpDown _nudCapacity  = new() { Minimum = 1, Maximum = 999, Value = 1 };
    private readonly Label         _lblPreview   = new() { AutoSize = true, ForeColor = Color.DimGray };

    public CreateBinsBulkForm(ILocationCommandRepository commandRepo, ILocationQueryRepository queryRepo)
    {
        _commandRepo = commandRepo;
        _queryRepo   = queryRepo;

        Text            = "Bulk Create Locations";
        Size            = new Size(480, 400);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        BuildLayout();
        LoadLookups();
        UpdatePreview();

        _txtPrefix.TextChanged    += (_, _) => UpdatePreview();
        _nudRowFrom.ValueChanged  += (_, _) => UpdatePreview();
        _nudRowTo.ValueChanged    += (_, _) => UpdatePreview();
        _txtColFrom.TextChanged   += (_, _) => UpdatePreview();
        _txtColTo.TextChanged     += (_, _) => UpdatePreview();
        _nudDepthFrom.ValueChanged += (_, _) => UpdatePreview();
        _nudDepthTo.ValueChanged  += (_, _) => UpdatePreview();
    }

    private void BuildLayout()
    {
        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            RowCount    = 11,
            Padding     = new Padding(12, 12, 12, 0)
        };
        for (int i = 0; i < 11; i++)
            table.RowStyles.Add(new RowStyle(SizeType.Absolute, 29f));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        // Row range — two NumericUpDowns side by side
        var pnlRows = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight };
        _nudRowFrom.Width = 60; _nudRowTo.Width = 60;
        var lblTo1 = new Label { Text = "to", AutoSize = true, Padding = new Padding(4, 6, 4, 0) };
        pnlRows.Controls.AddRange([_nudRowFrom, lblTo1, _nudRowTo]);

        var pnlCols = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight };
        _txtColFrom.Width = 36; _txtColTo.Width = 36;
        var lblTo2 = new Label { Text = "to", AutoSize = true, Padding = new Padding(4, 6, 4, 0) };
        pnlCols.Controls.AddRange([_txtColFrom, lblTo2, _txtColTo]);

        var pnlDepth = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight };
        _nudDepthFrom.Width = 60; _nudDepthTo.Width = 60;
        var lblTo3 = new Label { Text = "to", AutoSize = true, Padding = new Padding(4, 6, 4, 0) };
        pnlDepth.Controls.AddRange([_nudDepthFrom, lblTo3, _nudDepthTo]);

        AddRow(table, 0,  "Prefix *",       _txtPrefix);
        AddRow(table, 1,  "Storage Type *", _cmbType);
        AddRow(table, 2,  "Zone",           _cmbZone);
        AddRow(table, 3,  "Rows",           pnlRows);
        AddRow(table, 4,  "Columns (A–Z)",  pnlCols);
        AddRow(table, 5,  "Depth",          pnlDepth);
        AddRow(table, 6,  "Capacity",       _nudCapacity);

        var row7Lbl = new Label { Text = "Preview", Dock = DockStyle.Fill, TextAlign = System.Drawing.ContentAlignment.MiddleRight, Font = new Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8.5f) };
        table.Controls.Add(row7Lbl, 0, 7);
        table.Controls.Add(_lblPreview, 1, 7);

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

    private void UpdatePreview()
    {
        var prefix = _txtPrefix.Text.Trim().ToUpper();
        var colFrom = _txtColFrom.Text.Length == 1 && char.IsLetter(_txtColFrom.Text[0]) ? char.ToUpper(_txtColFrom.Text[0]) : 'A';
        var colTo   = _txtColTo.Text.Length == 1   && char.IsLetter(_txtColTo.Text[0])   ? char.ToUpper(_txtColTo.Text[0])   : 'A';

        var rows   = Math.Max(0, (int)_nudRowTo.Value - (int)_nudRowFrom.Value + 1);
        var cols   = Math.Max(0, colTo - colFrom + 1);
        var depths = Math.Max(0, (int)_nudDepthTo.Value - (int)_nudDepthFrom.Value + 1);
        var total  = rows * cols * depths;

        var first = $"{prefix}{_nudRowFrom.Value:00}{colFrom}{_nudDepthFrom.Value}";
        var last  = $"{prefix}{_nudRowTo.Value:00}{colTo}{_nudDepthTo.Value}";

        _lblPreview.Text = total > 0
            ? $"{first} → {last}  ({total} locations)"
            : "(invalid range)";
    }

    private void BtnCreate_Click(object? sender, EventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_txtPrefix.Text))
        { Msg("Prefix is required."); return; }

        if (_cmbType.SelectedIndex == 0)
        { Msg("Please select a storage type."); return; }

        if (_txtColFrom.Text.Length != 1 || !char.IsLetter(_txtColFrom.Text[0]))
        { Msg("Column From must be a single letter A–Z."); return; }

        if (_txtColTo.Text.Length != 1 || !char.IsLetter(_txtColTo.Text[0]))
        { Msg("Column To must be a single letter A–Z."); return; }

        var zone = _cmbZone.SelectedIndex > 0 ? _cmbZone.SelectedItem?.ToString() : null;

        var result = _commandRepo.CreateBinsBulk(
            prefix:          _txtPrefix.Text.Trim().ToUpper(),
            storageTypeCode: _cmbType.SelectedItem!.ToString()!,
            rowFrom:         (int)_nudRowFrom.Value,
            rowTo:           (int)_nudRowTo.Value,
            colFrom:         char.ToUpper(_txtColFrom.Text[0]),
            colTo:           char.ToUpper(_txtColTo.Text[0]),
            depthFrom:       (int)_nudDepthFrom.Value,
            depthTo:         (int)_nudDepthTo.Value,
            zoneCode:        zone,
            capacity:        (int)_nudCapacity.Value);

        if (!result.Success)
        { Msg(result.FriendlyMessage); return; }

        MessageBox.Show(this,
            result.FriendlyMessage,
            "Locations Created",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);

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
