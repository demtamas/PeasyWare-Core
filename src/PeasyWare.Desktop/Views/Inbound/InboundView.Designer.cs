namespace PeasyWare.Desktop.Views.Inbound
{
    partial class InboundView
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
            dgvInbound = new System.Windows.Forms.DataGridView();
            ((System.ComponentModel.ISupportInitialize)dgvInbound).BeginInit();
            SuspendLayout();

            dgvInbound.ColumnHeadersHeightSizeMode = System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            dgvInbound.Dock     = System.Windows.Forms.DockStyle.Fill;
            dgvInbound.Location = new System.Drawing.Point(0, 0);
            dgvInbound.Name     = "dgvInbound";
            dgvInbound.Size     = new System.Drawing.Size(1200, 686);
            dgvInbound.TabIndex = 0;

            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(dgvInbound);
            Name = "InboundView";
            Size = new System.Drawing.Size(1200, 686);

            ((System.ComponentModel.ISupportInitialize)dgvInbound).EndInit();
            ResumeLayout(false);
        }

        private System.Windows.Forms.DataGridView dgvInbound;
    }
}
