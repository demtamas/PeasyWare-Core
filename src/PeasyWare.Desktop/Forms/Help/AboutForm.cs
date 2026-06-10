using System;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms.Help;

public sealed class AboutForm : Form
{
    public AboutForm()
    {
        Text            = "About PeasyWare";
        Size            = new Size(420, 340);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        BuildLayout();
    }

    private void BuildLayout()
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 80, BackColor = Color.FromArgb(30, 30, 35) };
        header.Controls.Add(new Label
        {
            Text      = "PeasyWare WMS",
            Dock      = DockStyle.Fill,
            ForeColor = Color.White,
            Font      = new Font("Segoe UI", 18f, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter
        });

        var version = Assembly.GetEntryAssembly()?.GetName().Version;
        var verStr  = version is not null ? $"v{version.Major}.{version.Minor}.{version.Build}" : "v1.0";

        var rows = new (string Key, string Val)[]
        {
            ("Version",   verStr),
            ("Edition",   "Standard"),
            ("",          ""),
            ("",          "Professional Warehouse Management System"),
            ("",          "Built for real warehouse operations."),
            ("",          ""),
            ("Author",    "Tamas Demjen"),
            ("Copyright", $"© {DateTime.UtcNow.Year}"),
            ("Stack",     "C# · .NET 10 · SQL Server · WinForms"),
            ("Licence",   "MIT")
        };

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            Padding     = new Padding(20, 16, 20, 0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 82));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var (key, val) in rows)
        {
            table.Controls.Add(Cell(key, right: true,  bold: true, color: Color.FromArgb(60, 60, 90)));
            table.Controls.Add(Cell(val, right: false, bold: false));
        }

        var footer  = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(0, 10, 16, 0) };
        var btnClose = new Button
        {
            Text         = "Close",
            Width        = 80,
            Height       = 28,
            DialogResult = DialogResult.Cancel,
            Dock         = DockStyle.Right
        };
        footer.Controls.Add(btnClose);

        Controls.Add(table);
        Controls.Add(footer);
        Controls.Add(header);
        CancelButton = btnClose;
    }

    private static Label Cell(string text, bool right, bool bold, Color? color = null)
    {
        var lbl = new Label
        {
            Text      = text,
            Dock      = DockStyle.Fill,
            TextAlign = right ? ContentAlignment.TopRight : ContentAlignment.TopLeft,
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f, bold ? FontStyle.Bold : FontStyle.Regular),
            Height    = 22,
            Padding   = new Padding(right ? 0 : 0, 3, right ? 8 : 0, 0)
        };
        if (color.HasValue) lbl.ForeColor = color.Value;
        return lbl;
    }
}
