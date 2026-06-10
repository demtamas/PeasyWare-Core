using PeasyWare.Application.Contexts;
using System;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms.Help;

public sealed class VersionInfoForm : Form
{
    public VersionInfoForm(SessionContext session, string dbServer, string dbName)
    {
        Text            = "Version Info";
        Size            = new Size(480, 340);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        BuildLayout(session, dbServer, dbName);
    }

    private void BuildLayout(SessionContext session, string dbServer, string dbName)
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 42, BackColor = Color.FromArgb(45, 45, 48) };
        header.Controls.Add(new Label
        {
            Text      = "Version Information",
            Dock      = DockStyle.Fill,
            ForeColor = Color.White,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            Padding   = new Padding(14, 10, 0, 0)
        });

        var asm     = Assembly.GetEntryAssembly();
        var version = asm?.GetName().Version;
        var verStr  = version is not null ? $"{version.Major}.{version.Minor}.{version.Build}.{version.Revision}" : "—";

        // Build date from linker timestamp (PE header trick)
        var buildDate = "—";
        try
        {
            var loc  = asm?.Location;
            if (loc is not null)
            {
                var bytes = System.IO.File.ReadAllBytes(loc);
                var secs  = BitConverter.ToInt32(bytes, BitConverter.ToInt32(bytes, 60) + 8);
                buildDate = DateTimeOffset.FromUnixTimeSeconds(secs).UtcDateTime.ToString("dd/MM/yyyy HH:mm") + " UTC";
            }
        }
        catch { /* non-critical */ }

        var rows = new (string Key, string Val)[]
        {
            ("App version",   verStr),
            ("Build date",    buildDate),
            (".NET runtime",  $"{Environment.Version}"),
            ("OS",            Environment.OSVersion.ToString()),
            ("Machine",       Environment.MachineName),
            ("",              ""),
            ("DB server",     dbServer),
            ("DB name",       dbName),
            ("Session ID",    session.SessionId.ToString()[..8] + "…"),
            ("User",          session.Username)
        };

        var table = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            ColumnCount = 2,
            Padding     = new Padding(16, 12, 16, 0)
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (var (key, val) in rows)
        {
            table.Controls.Add(Caption(key));
            table.Controls.Add(Value(val));
        }

        var footer   = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(0, 10, 16, 0) };
        var btnCopy  = new Button { Text = "Copy to clipboard", Width = 130, Height = 28, Location = new Point(16, 10) };
        var btnClose = new Button { Text = "Close", Width = 80, Height = 28, DialogResult = DialogResult.Cancel, Dock = DockStyle.Right };

        btnCopy.Click += (_, _) =>
        {
            var sb = new System.Text.StringBuilder();
            foreach (var (k, v) in rows)
                if (!string.IsNullOrEmpty(k)) sb.AppendLine($"{k}: {v}");
            try { Clipboard.SetText(sb.ToString()); } catch { }
        };

        footer.Controls.AddRange(new Control[] { btnCopy, btnClose });

        Controls.Add(table);
        Controls.Add(footer);
        Controls.Add(header);
        CancelButton = btnClose;
    }

    private static Label Caption(string t) => new()
    {
        Text      = t,
        Dock      = DockStyle.Fill,
        TextAlign = ContentAlignment.TopRight,
        Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f, FontStyle.Bold),
        ForeColor = Color.FromArgb(60, 60, 90),
        Height    = 22,
        Padding   = new Padding(0, 3, 8, 0)
    };

    private static Label Value(string t) => new()
    {
        Text      = t,
        Dock      = DockStyle.Fill,
        TextAlign = ContentAlignment.TopLeft,
        Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f),
        Height    = 22,
        Padding   = new Padding(0, 3, 0, 0)
    };
}
