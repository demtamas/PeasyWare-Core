using PeasyWare.Application.Dto;
using PeasyWare.Application.Interfaces;
using PeasyWare.Application.Security;
using PeasyWare.Desktop.Forms;
using PeasyWare.Desktop.Forms.Settings;
using PeasyWare.Desktop.Infrastructure;
using PeasyWare.Desktop.Infrastructure.Ui;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Settings;

public partial class SettingsView : BaseView, IToolbarAware
{
    private readonly Guid _sessionId;
    private readonly ISettingsQueryRepository _queryRepo;
    private readonly ISettingsCommandRepository _commandRepo;

    private ToolStripButton? _btnRefresh;
    private ToolStripButton? _btnEdit;

    // reusable font (important for DataGridView painting)
    private readonly Font _categoryFont = new(SystemFonts.DefaultFont, FontStyle.Bold);

    public SettingsView(
        Guid sessionId,
        ISettingsQueryRepository queryRepo,
        ISettingsCommandRepository commandRepo)
    {
        InitializeComponent();

        _sessionId = sessionId;
        _queryRepo = queryRepo;
        _commandRepo = commandRepo;

        ConfigureGrid(dgvSettings);
        EnableDoubleBuffering(dgvSettings);

        dgvSettings.CellFormatting += DgvSettings_CellFormatting;
        dgvSettings.RowPrePaint += DgvSettings_RowPrePaint;
        dgvSettings.SelectionChanged += DgvSettings_SelectionChanged;
    }

    public void ActivateView()
    {
        LoadSettings();
    }

    private void DgvSettings_SelectionChanged(object? sender, EventArgs e)
    {
        UpdateToolbarState();
    }

    // ==========================================================
    // Toolbar
    // ==========================================================

    public void ConfigureToolbar(ToolStrip toolStrip)
    {
        toolStrip.Items.Clear();
        toolStrip.ImageScalingSize = new Size(16, 16);

        _btnRefresh = new ToolStripButton("Refresh")
        {
            Image = Icons.Refresh,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnRefresh.Click += Wrap(LoadSettings);

        _btnEdit = new ToolStripButton("Edit highlighted")
        {
            //Image = Icons.Edit,
            Enabled = false,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        };
        _btnEdit.Click += Wrap(EditSelectedSetting);

        toolStrip.Items.Add(_btnRefresh);
        toolStrip.Items.Add(new ToolStripSeparator());
        toolStrip.Items.Add(_btnEdit);

        UpdateToolbarState();
    }

    private void UpdateToolbarState()
    {
        if (_btnEdit == null)
            return;

        _btnEdit.Enabled = GetSelectedSetting() != null;
    }

    // ==========================================================
    // Load
    // ==========================================================

    private void LoadSettings()
    {
        if (FindForm() is not MainForm main)
            return;

        main.ExecuteWithSession(() =>
        {
            var raw = _queryRepo.GetSettings()
                .OrderBy(s => s.CategoryOrder)
                .ThenBy(s => s.DisplayOrder)
                .ToList();

            var rows = new List<SettingRow>();

            foreach (var group in raw.GroupBy(s => s.Category))
            {
                rows.Add(new SettingRow
                {
                    IsCategoryHeader = true,
                    CategoryName = group.First().CategoryName
                });

                rows.AddRange(group.Select(s => new SettingRow
                {
                    Setting = s
                }));
            }

            dgvSettings.DataSource = null;
            dgvSettings.DataSource = rows;

            dgvSettings.ClearSelection();

            UpdateToolbarState();
        });
    }

    private SettingDto? GetSelectedSetting()
    {
        if (dgvSettings.CurrentRow?.DataBoundItem is not SettingRow row)
            return null;

        return row.IsCategoryHeader ? null : row.Setting;
    }

    // ==========================================================
    // Edit
    // ==========================================================

    private void EditSelectedSetting()
    {
        if (FindForm() is MainForm main && main.GetIsSessionExpired())
            return;

        var setting = GetSelectedSetting();
        if (setting == null)
            return;

        using var dlg = new SettingEditForm(setting);

        if (dlg.ShowDialog(this) != DialogResult.OK)
            return;

        var result = _commandRepo.UpdateSetting(
            setting.SettingName,
            dlg.NewValue ?? "");

        if (!result.Success)
        {
            MessageBox.Show(
                result.FriendlyMessage ?? "Update failed.",
                "Settings",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return;
        }

        MessageBox.Show(
            this,
            result.FriendlyMessage ?? "Setting updated successfully.",
            "PeasyWare Settings",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);

        LoadSettings();
    }

    // ==========================================================
    // Grid
    // ==========================================================

    private static void ConfigureGrid(DataGridView dgv)
    {
        dgv.AutoGenerateColumns = false;
        dgv.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
        dgv.MultiSelect = false;
        dgv.ReadOnly = true;

        dgv.AllowUserToAddRows = false;
        dgv.AllowUserToDeleteRows = false;
        dgv.AllowUserToResizeRows = false;

        dgv.RowHeadersVisible = false;
        dgv.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        dgv.EnableHeadersVisualStyles = false;

        dgv.ColumnHeadersDefaultCellStyle.BackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.ForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = SystemColors.ControlText;
        dgv.ColumnHeadersDefaultCellStyle.Font = new Font(dgv.Font, FontStyle.Bold);

        dgv.DefaultCellStyle.SelectionBackColor = Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor = Color.Black;

        dgv.Columns.Clear();

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(SettingRow.DisplayName),
            HeaderText = "Setting",
            ReadOnly = true,
            FillWeight = 24
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(SettingRow.SettingValue),
            HeaderText = "Value",
            FillWeight = 12
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(SettingRow.DataType),
            HeaderText = "Type",
            ReadOnly = true,
            FillWeight = 8
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(SettingRow.Description),
            HeaderText = "Description",
            ReadOnly = true,
            FillWeight = 36
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(SettingRow.UpdatedByUsername),
            HeaderText = "Updated By",
            ReadOnly = true,
            FillWeight = 10
        });

        dgv.Columns.Add(new DataGridViewTextBoxColumn
        {
            DataPropertyName = nameof(SettingRow.UpdatedAt),
            HeaderText = "Updated",
            ReadOnly = true,
            FillWeight = 12,
            DefaultCellStyle = new DataGridViewCellStyle
            {
                Format = "yyyy-MM-dd HH:mm:ss"
            }
        });
    }

    private static void EnableDoubleBuffering(DataGridView dgv)
    {
        typeof(DataGridView)
            .GetProperty(
                "DoubleBuffered",
                System.Reflection.BindingFlags.Instance |
                System.Reflection.BindingFlags.NonPublic)
            ?.SetValue(dgv, true, null);
    }

    // ==========================================================
    // Formatting
    // ==========================================================

    private void DgvSettings_CellFormatting(object? sender, DataGridViewCellFormattingEventArgs e)
    {
        if (e.RowIndex < 0)
            return;

        if (dgvSettings.Rows[e.RowIndex].DataBoundItem is not SettingRow row)
            return;

        var setting = row.Setting;
        if (setting == null)
            return;

        var column = dgvSettings.Columns[e.ColumnIndex];

        if (column.DataPropertyName == nameof(SettingRow.SettingValue))
        {
            if (setting.IsBoolean)
            {
                if (bool.TryParse(setting.SettingValue, out var value))
                    e.Value = value ? "Enabled" : "Disabled";
            }
            else if (setting.IsSensitive && setting.SettingValue != null)
            {
                e.Value = new string('●', Math.Min(8, setting.SettingValue.Length));
            }
        }
    }

    // ==========================================================
    // Row styling
    // ==========================================================

    private void DgvSettings_RowPrePaint(object? sender, DataGridViewRowPrePaintEventArgs e)
    {
        if (e.RowIndex < 0)
            return;

        if (dgvSettings.Rows[e.RowIndex].DataBoundItem is not SettingRow row)
            return;

        var gridRow = dgvSettings.Rows[e.RowIndex];

        if (row.IsCategoryHeader)
        {
            gridRow.DefaultCellStyle.BackColor = Color.Gainsboro;
            gridRow.DefaultCellStyle.Font = _categoryFont;
            return;
        }

        if (row.Setting?.IsSensitive == true)
            gridRow.DefaultCellStyle.BackColor = Color.LemonChiffon;
        else
            gridRow.DefaultCellStyle.BackColor = Color.White;
    }

    // ==========================================================
    // Cleanup
    // ==========================================================

}