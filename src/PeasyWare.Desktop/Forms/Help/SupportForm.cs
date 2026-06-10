using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms.Help;

public sealed class SupportForm : Form
{
    public SupportForm(string sessionId, string appVersion, string schemaVersion)
    {
        Text            = "Support";
        Size            = new Size(460, 340);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        MinimizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;
        BuildLayout(sessionId, appVersion, schemaVersion);
    }

    private void BuildLayout(string sessionId, string appVersion, string schemaVersion)
    {
        var header = new Panel { Dock = DockStyle.Top, Height = 42, BackColor = Color.FromArgb(45, 45, 48) };
        header.Controls.Add(new Label
        {
            Text      = "Support",
            Dock      = DockStyle.Fill,
            ForeColor = Color.White,
            Font      = new Font(Font.FontFamily, 10f, FontStyle.Bold),
            Padding   = new Padding(14, 10, 0, 0)
        });

        var body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(16, 12, 16, 0) };

        // GitHub link
        var lblLink = new LinkLabel
        {
            Text      = "https://github.com/demtamas/PeasyWare-Core/issues",
            AutoSize  = true,
            Location  = new Point(0, 8),
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f)
        };
        lblLink.LinkClicked += (_, _) =>
        {
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName        = "https://github.com/demtamas/PeasyWare-Core/issues",
                UseShellExecute = true
            }); } catch { }
        };

        var lblIssue = new Label
        {
            Text      = "To report a bug or request a feature, open an issue on GitHub.\nInclude the diagnostic info below when reporting.",
            AutoSize  = false,
            Width     = 420,
            Height    = 36,
            Location  = new Point(0, 32),
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f),
            ForeColor = Color.DimGray
        };

        // Diagnostic summary
        var diag = $"App: {appVersion}  |  Schema: {schemaVersion}  |  Session: {sessionId[..8]}…";
        var lblDiag = new Label
        {
            Text      = diag,
            AutoSize  = false,
            Width     = 420,
            Height    = 22,
            Location  = new Point(0, 76),
            Font      = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f, FontStyle.Bold),
            ForeColor = Color.FromArgb(40, 40, 80),
            BackColor = Color.FromArgb(240, 243, 255),
            Padding   = new Padding(6, 4, 0, 0),
            BorderStyle = BorderStyle.FixedSingle
        };

        var btnCopy = new Button
        {
            Text     = "Copy diagnostic info",
            Width    = 140,
            Height   = 28,
            Location = new Point(0, 108),
            Font     = new Font(SystemFonts.DefaultFont.FontFamily, 8.5f)
        };
        btnCopy.Click += (_, _) =>
        {
            var full = $"PeasyWare Diagnostic Info\n" +
                       $"App version:    {appVersion}\n" +
                       $"Schema version: {schemaVersion}\n" +
                       $"Session ID:     {sessionId}\n" +
                       $"Machine:        {Environment.MachineName}\n" +
                       $"OS:             {Environment.OSVersion}\n" +
                       $".NET:           {Environment.Version}\n" +
                       $"Timestamp:      {DateTime.UtcNow:dd/MM/yyyy HH:mm:ss} UTC";
            try { Clipboard.SetText(full); } catch { }
        };

        body.Controls.AddRange(new Control[] { lblLink, lblIssue, lblDiag, btnCopy });

        var footer   = new Panel { Dock = DockStyle.Bottom, Height = 50, Padding = new Padding(0, 10, 16, 0) };
        var btnClose = new Button
        {
            Text         = "Close",
            Width        = 80,
            Height       = 28,
            DialogResult = DialogResult.Cancel,
            Dock         = DockStyle.Right
        };
        footer.Controls.Add(btnClose);

        Controls.Add(body);
        Controls.Add(footer);
        Controls.Add(header);
        CancelButton = btnClose;
    }
}
