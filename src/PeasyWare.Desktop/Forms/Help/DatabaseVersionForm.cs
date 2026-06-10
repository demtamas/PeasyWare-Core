using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms.Help;

public sealed class DatabaseVersionForm : Form
{
    public DatabaseVersionForm(string schemaVersion, string dbServer, string dbName, DateTime? schemaUpdated)
    {
        Text            = "Database Version";
        Size            = new Size(440, 280);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        BuildLayout(schemaVersion, dbServer, dbName, schemaUpdated);
    }

    private void BuildLayout(string schemaVersion, string dbServer, string dbName, DateTime? schemaUpdated)
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 42, BackColor = Color.FromArgb(45, 45, 48) };
        header.Controls.Add(new Label
        {
            Text      = "Database Version",
            Dock      = DockStyle.Fill,
            ForeColor = Color.White,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            Padding   = new Padding(14, 10, 0, 0)
        });

        var rows = new (string Key, string Val)[]
        {
            ("Server",         dbServer),
            ("Database",       dbName),
            ("",               ""),
            ("Schema version", schemaVersion),
            ("Schema updated", schemaUpdated?.ToString("dd/MM/yyyy HH:mm") + " UTC" ?? "—"),
            ("",               ""),
            ("Migration path", "Settings: core.schema_version"),
            ("",               "Future migrations bump this value on deploy.")
        };

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            Padding     = new Padding(16, 12, 16, 0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var (k, v) in rows)
        {
            var isHeading = k == "Schema version";
            var cap = new Label
            {
                Text      = k,
                Dock      = DockStyle.Fill,
                TextAlign = ContentAlignment.TopRight,
                Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(60, 60, 90),
                Height    = 22,
                Padding   = new Padding(0, 3, 8, 0)
            };
            var val = new Label
            {
                Text      = v,
                Dock      = DockStyle.Fill,
                TextAlign = ContentAlignment.TopLeft,
                Font      = new Font(SystemFonts.DefaultFont.FontFamily, isHeading ? 10f : 8.5f,
                                     isHeading ? FontStyle.Bold : FontStyle.Regular),
                ForeColor = isHeading ? Color.DarkGreen : SystemColors.WindowText,
                Height    = isHeading ? 26 : 22,
                Padding   = new Padding(0, 3, 0, 0)
            };
            table.Controls.Add(cap);
            table.Controls.Add(val);
        }

        var footer   = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(0, 10, 16, 0) };
        var btnClose = new Button { Text = "Close", Width = 80, Height = 28, DialogResult = DialogResult.Cancel, Dock = DockStyle.Right };
        footer.Controls.Add(btnClose);

        Controls.Add(table);
        Controls.Add(footer);
        Controls.Add(header);
        CancelButton = btnClose;
    }
}
