namespace PeasyWare.Desktop.Views.Parties
{
    partial class PartiesView
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
            dgvParties = new System.Windows.Forms.DataGridView();
            ((System.ComponentModel.ISupportInitialize)dgvParties).BeginInit();
            SuspendLayout();

            dgvParties.Dock     = System.Windows.Forms.DockStyle.Fill;
            dgvParties.Name     = "dgvParties";
            dgvParties.TabIndex = 0;

            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(dgvParties);
            Name = "PartiesView";
            Size = new System.Drawing.Size(1200, 686);

            ((System.ComponentModel.ISupportInitialize)dgvParties).EndInit();
            ResumeLayout(false);
        }

        private System.Windows.Forms.DataGridView dgvParties;
    }
}
