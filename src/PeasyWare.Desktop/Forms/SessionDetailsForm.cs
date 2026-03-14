using PeasyWare.Application.Dto;
using System;
using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Forms
{
    public partial class SessionDetailsForm : Form
    {
        private readonly SessionDetailsDto _details;

        public SessionDetailsForm(SessionDetailsDto details)
        {
            InitializeComponent();

            _details = details ?? throw new ArgumentNullException(nameof(details));

            BuildLayout(_details);
        }

        // --------------------------------------------------
        // Layout builder
        // --------------------------------------------------

        private void BuildLayout(SessionDetailsDto d)
        {
            tableLayoutPanel1.SuspendLayout();

            tableLayoutPanel1.Controls.Clear();
            tableLayoutPanel1.RowStyles.Clear();
            tableLayoutPanel1.RowCount = 0;

            AddSection("Session");
            AddRow("Session ID", d.SessionId.ToString());
            AddRow("Active", d.IsActive ? "Yes" : "No");
            AddRow("Login Time", d.LoginTime.ToString("yyyy-MM-dd HH:mm:ss"));
            AddRow("Last Seen", d.LastSeen.ToString("yyyy-MM-dd HH:mm:ss"));

            AddSection("User");
            AddRow("Username", d.Username);
            AddRow("Display Name", d.DisplayName);

            AddSection("Client");
            AddRow("Application", d.ClientApp ?? "(none)");
            AddRow("Machine", d.ClientInfo ?? "(none)");
            AddRow("IP Address", d.IpAddress ?? "(none)");
            AddRow("OS", d.OsInfo ?? "(none)");

            AddSpacer(16);

            AddRow("Correlation ID", d.CorrelationId ?? "(none)");


            tableLayoutPanel1.ResumeLayout();
        }

        // --------------------------------------------------
        // Helpers
        // --------------------------------------------------

        private void AddSection(string title)
        {
            var rowIndex = tableLayoutPanel1.RowCount;

            tableLayoutPanel1.RowCount++;
            tableLayoutPanel1.RowStyles.Add(
                new RowStyle(SizeType.AutoSize));

            var lbl = new Label
            {
                Text = title,
                Font = new Font(Font, FontStyle.Bold),
                ForeColor = SystemColors.ControlDarkDark,
                Dock = DockStyle.Fill,
                Padding = new Padding(0, 24, 0, 6)
            };

            tableLayoutPanel1.Controls.Add(lbl, 0, rowIndex);
            tableLayoutPanel1.SetColumnSpan(lbl, 2);
        }

        private void AddRow(string label, string value)
        {
            var rowIndex = tableLayoutPanel1.RowCount;

            tableLayoutPanel1.RowCount++;
            tableLayoutPanel1.RowStyles.Add(
                new RowStyle(SizeType.AutoSize));

            var lbl = new Label
            {
                Text = label,
                AutoSize = true,
                ForeColor = SystemColors.GrayText,
                TextAlign = ContentAlignment.MiddleRight,
                Anchor = AnchorStyles.Right,
                Dock = DockStyle.None,
                Padding = new Padding(0, 4, 8, 4)
            };

            var txt = new TextBox
            {
                Text = value,
                ReadOnly = true,
                BorderStyle = BorderStyle.None,
                BackColor = SystemColors.Control,
                Dock = DockStyle.Fill,
                Margin = new Padding(0, 4, 0, 4),
                TabStop = false
            };

            // Monospace for forensic identifiers
            if (label.Contains("Correlation"))
            {
                txt.Font = new Font(FontFamily.GenericMonospace, txt.Font.Size);
                txt.BackColor = SystemColors.ControlLight;
            }

            tableLayoutPanel1.Controls.Add(lbl, 0, rowIndex);
            tableLayoutPanel1.Controls.Add(txt, 1, rowIndex);
        }
        private void AddSpacer(int height = 12)
        {
            var rowIndex = tableLayoutPanel1.RowCount;

            tableLayoutPanel1.RowCount++;
            tableLayoutPanel1.RowStyles.Add(
                new RowStyle(SizeType.Absolute, height));

            tableLayoutPanel1.Controls.Add(
                new Label { Height = height },
                0,
                rowIndex);

            tableLayoutPanel1.SetColumnSpan(
                tableLayoutPanel1.Controls[^1],
                2);
        }

    }
}
