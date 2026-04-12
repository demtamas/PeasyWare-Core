using PeasyWare.Application.Dto;
using System;
using System.Linq;
using System.Text.Json;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms.Settings;

public partial class SettingEditForm : Form
{
    private readonly SettingDto _setting;

    public string? NewValue { get; private set; }

    public SettingEditForm(SettingDto setting)
    {
        _setting = setting ?? throw new ArgumentNullException(nameof(setting));

        InitializeComponent();

        ConfigureWindow();
        InitializeForm();
    }

    // --------------------------------------------------
    // Window setup
    // --------------------------------------------------

    private void ConfigureWindow()
    {
        Text = $"Edit setting – {_setting.DisplayName ?? _setting.SettingName}";
    }

    // --------------------------------------------------
    // Initial UI state
    // --------------------------------------------------

    private void InitializeForm()
    {
        lblSettingName.Text = _setting.DisplayName ?? _setting.SettingName;
        lblDescription.Text = _setting.Description ?? "";
        lblType.Text = _setting.DataType ?? "";

        BuildEditor();
    }

    // --------------------------------------------------
    // Editor selection
    // --------------------------------------------------

    private void BuildEditor()
    {
        HideAllEditors();

        if (_setting.IsBoolean)
        {
            BuildBooleanEditor();
            return;
        }

        if (_setting.IsEnum && !string.IsNullOrWhiteSpace(_setting.ValidationRule))
        {
            if (BuildEnumEditor())
                return;
        }

        if (_setting.IsRange)
        {
            BuildRangeEditor();
            return;
        }

        BuildTextEditor();
    }

    private void HideAllEditors()
    {
        chkValue.Visible = false;
        txtValue.Visible = false;
        cmbValue.Visible = false;
        numValue.Visible = false;
    }

    private void BuildBooleanEditor()
    {
        chkValue.Visible = true;

        if (bool.TryParse(_setting.SettingValue, out var value))
            chkValue.Checked = value;
    }

    private bool BuildEnumEditor()
    {
        try
        {
            using var doc = JsonDocument.Parse(_setting.ValidationRule!);

            if (!doc.RootElement.TryGetProperty("values", out var values))
                return false;

            var items = values
                .EnumerateArray()
                .Select(v => v.GetString())
                .Where(v => !string.IsNullOrWhiteSpace(v))
                .Cast<object>()
                .ToArray();

            if (items.Length == 0)
                return false;

            cmbValue.Visible = true;
            cmbValue.Items.AddRange(items);

            if (_setting.SettingValue != null)
                cmbValue.SelectedItem = _setting.SettingValue;

            return true;
        }
        catch
        {
            return false;
        }
    }

    private void BuildRangeEditor()
    {
        numValue.Visible = true;

        if (_setting.RangeMin.HasValue)
            numValue.Minimum = _setting.RangeMin.Value;

        if (_setting.RangeMax.HasValue)
            numValue.Maximum = _setting.RangeMax.Value;

        if (int.TryParse(_setting.SettingValue, out var n))
            numValue.Value = n;
    }

    private void BuildTextEditor()
    {
        txtValue.Visible = true;
        txtValue.Text = _setting.SettingValue ?? "";
    }

    // --------------------------------------------------
    // Save
    // --------------------------------------------------

    private void btnSave_Click(object sender, EventArgs e)
    {
        if (_setting.IsBoolean)
        {
            NewValue = chkValue.Checked ? "true" : "false";
        }
        else if (_setting.IsEnum && cmbValue.Visible)
        {
            NewValue = cmbValue.SelectedItem?.ToString();
        }
        else if (_setting.IsRange && numValue.Visible)
        {
            NewValue = numValue.Value.ToString();
        }
        else
        {
            NewValue = txtValue.Text;
        }

        DialogResult = DialogResult.OK;
    }
}