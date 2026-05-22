namespace PeasyWare.Desktop.Forms.Settings
{
    partial class SettingEditForm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
                components.Dispose();
            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            pnlHeader     = new System.Windows.Forms.Panel();
            lblSettingName = new System.Windows.Forms.Label();
            lblSubtitle    = new System.Windows.Forms.Label();
            pnlBody        = new System.Windows.Forms.Panel();
            lblDescHeader  = new System.Windows.Forms.Label();
            lblDescription = new System.Windows.Forms.Label();
            lblTypeHeader  = new System.Windows.Forms.Label();
            lblType        = new System.Windows.Forms.Label();
            lblValueHeader = new System.Windows.Forms.Label();
            chkValue       = new System.Windows.Forms.CheckBox();
            txtValue       = new System.Windows.Forms.TextBox();
            cmbValue       = new System.Windows.Forms.ComboBox();
            numValue       = new System.Windows.Forms.NumericUpDown();
            pnlFooter      = new System.Windows.Forms.Panel();
            btnSave        = new System.Windows.Forms.Button();
            btnCancel      = new System.Windows.Forms.Button();

            pnlHeader.SuspendLayout();
            pnlBody.SuspendLayout();
            pnlFooter.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)numValue).BeginInit();
            SuspendLayout();

            // ── Header panel ────────────────────────────────────────────
            pnlHeader.Dock = System.Windows.Forms.DockStyle.Top;
            pnlHeader.Height = 56;
            pnlHeader.Padding = new System.Windows.Forms.Padding(16, 10, 16, 8);
            pnlHeader.BackColor = System.Drawing.Color.FromArgb(45, 45, 48);
            pnlHeader.Controls.Add(lblSubtitle);
            pnlHeader.Controls.Add(lblSettingName);

            lblSettingName.AutoSize  = false;
            lblSettingName.Dock      = System.Windows.Forms.DockStyle.Top;
            lblSettingName.Height    = 22;
            lblSettingName.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 11f, System.Drawing.FontStyle.Bold);
            lblSettingName.ForeColor = System.Drawing.Color.White;
            lblSettingName.Text      = "Setting name";

            lblSubtitle.AutoSize  = false;
            lblSubtitle.Dock      = System.Windows.Forms.DockStyle.Top;
            lblSubtitle.Height    = 16;
            lblSubtitle.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8.5f);
            lblSubtitle.ForeColor = System.Drawing.Color.Silver;
            lblSubtitle.Text      = "Edit operational setting";

            // ── Body panel ──────────────────────────────────────────────
            pnlBody.Dock    = System.Windows.Forms.DockStyle.Fill;
            pnlBody.Padding = new System.Windows.Forms.Padding(16, 12, 16, 0);
            pnlBody.Controls.Add(cmbValue);
            pnlBody.Controls.Add(numValue);
            pnlBody.Controls.Add(txtValue);
            pnlBody.Controls.Add(chkValue);
            pnlBody.Controls.Add(lblValueHeader);
            pnlBody.Controls.Add(lblType);
            pnlBody.Controls.Add(lblTypeHeader);
            pnlBody.Controls.Add(lblDescription);
            pnlBody.Controls.Add(lblDescHeader);

            // Description section
            lblDescHeader.AutoSize  = false;
            lblDescHeader.Location  = new System.Drawing.Point(16, 12);
            lblDescHeader.Size      = new System.Drawing.Size(440, 16);
            lblDescHeader.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8f, System.Drawing.FontStyle.Bold);
            lblDescHeader.ForeColor = System.Drawing.SystemColors.GrayText;
            lblDescHeader.Text      = "DESCRIPTION";

            lblDescription.AutoSize   = false;
            lblDescription.Location   = new System.Drawing.Point(16, 30);
            lblDescription.Size       = new System.Drawing.Size(440, 40);
            lblDescription.Font       = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 9f);
            lblDescription.ForeColor  = System.Drawing.SystemColors.ControlText;
            lblDescription.Text       = "";

            // Type section
            lblTypeHeader.AutoSize  = false;
            lblTypeHeader.Location  = new System.Drawing.Point(16, 80);
            lblTypeHeader.Size      = new System.Drawing.Size(440, 16);
            lblTypeHeader.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8f, System.Drawing.FontStyle.Bold);
            lblTypeHeader.ForeColor = System.Drawing.SystemColors.GrayText;
            lblTypeHeader.Text      = "TYPE";

            lblType.AutoSize  = false;
            lblType.Location  = new System.Drawing.Point(16, 97);
            lblType.Size      = new System.Drawing.Size(440, 18);
            lblType.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 9f);
            lblType.ForeColor = System.Drawing.SystemColors.ControlText;
            lblType.Text      = "";

            // Value section
            lblValueHeader.AutoSize  = false;
            lblValueHeader.Location  = new System.Drawing.Point(16, 130);
            lblValueHeader.Size      = new System.Drawing.Size(440, 16);
            lblValueHeader.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 8f, System.Drawing.FontStyle.Bold);
            lblValueHeader.ForeColor = System.Drawing.SystemColors.GrayText;
            lblValueHeader.Text      = "VALUE";

            // Checkbox (bool)
            chkValue.AutoSize = false;
            chkValue.Location = new System.Drawing.Point(16, 150);
            chkValue.Size     = new System.Drawing.Size(200, 28);
            chkValue.Font     = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 10f);
            chkValue.Text     = "Enabled";
            chkValue.Visible  = false;

            // Text (string)
            txtValue.Location = new System.Drawing.Point(16, 150);
            txtValue.Size     = new System.Drawing.Size(440, 28);
            txtValue.Font     = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 10f);
            txtValue.Visible  = false;

            // Combo (enum)
            cmbValue.Location      = new System.Drawing.Point(16, 150);
            cmbValue.Size          = new System.Drawing.Size(300, 28);
            cmbValue.Font          = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 10f);
            cmbValue.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            cmbValue.Visible       = false;

            // Numeric (range)
            numValue.Location = new System.Drawing.Point(16, 150);
            numValue.Size     = new System.Drawing.Size(160, 28);
            numValue.Font     = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 10f);
            numValue.Maximum  = new decimal(new int[] { 1000000, 0, 0, 0 });
            numValue.Visible  = false;

            // ── Footer panel ────────────────────────────────────────────
            pnlFooter.Dock      = System.Windows.Forms.DockStyle.Bottom;
            pnlFooter.Height    = 52;
            pnlFooter.Padding   = new System.Windows.Forms.Padding(12, 10, 12, 10);
            pnlFooter.BackColor = System.Drawing.SystemColors.Control;
            pnlFooter.Controls.Add(btnCancel);
            pnlFooter.Controls.Add(btnSave);

            btnSave.Text      = "&Save";
            btnSave.Size      = new System.Drawing.Size(100, 30);
            btnSave.Location  = new System.Drawing.Point(12, 10);
            btnSave.Font      = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 9f);
            btnSave.Click    += btnSave_Click;

            btnCancel.Text        = "&Cancel";
            btnCancel.Size        = new System.Drawing.Size(100, 30);
            btnCancel.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            btnCancel.Anchor      = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            btnCancel.Location    = new System.Drawing.Point(360, 10);
            btnCancel.Font        = new System.Drawing.Font(System.Drawing.SystemFonts.DefaultFont.FontFamily, 9f);

            // ── Form ────────────────────────────────────────────────────
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize          = new System.Drawing.Size(480, 320);
            FormBorderStyle     = System.Windows.Forms.FormBorderStyle.FixedDialog;
            MaximizeBox         = false;
            MinimizeBox         = false;
            StartPosition       = System.Windows.Forms.FormStartPosition.CenterParent;
            AcceptButton        = btnSave;
            CancelButton        = btnCancel;
            Text                = "Edit setting";

            Controls.Add(pnlBody);
            Controls.Add(pnlFooter);
            Controls.Add(pnlHeader);

            pnlHeader.ResumeLayout(false);
            pnlBody.ResumeLayout(false);
            pnlFooter.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)numValue).EndInit();
            ResumeLayout(false);
        }

        private System.Windows.Forms.Panel     pnlHeader;
        private System.Windows.Forms.Panel     pnlBody;
        private System.Windows.Forms.Panel     pnlFooter;
        private System.Windows.Forms.Label     lblSettingName;
        private System.Windows.Forms.Label     lblSubtitle;
        private System.Windows.Forms.Label     lblDescHeader;
        private System.Windows.Forms.Label     lblDescription;
        private System.Windows.Forms.Label     lblTypeHeader;
        private System.Windows.Forms.Label     lblType;
        private System.Windows.Forms.Label     lblValueHeader;
        private System.Windows.Forms.CheckBox  chkValue;
        private System.Windows.Forms.TextBox   txtValue;
        private System.Windows.Forms.ComboBox  cmbValue;
        private System.Windows.Forms.NumericUpDown numValue;
        private System.Windows.Forms.Button    btnSave;
        private System.Windows.Forms.Button    btnCancel;
    }
}
