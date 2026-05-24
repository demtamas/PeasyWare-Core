namespace PeasyWare.Desktop.Views.Movements
{
    partial class MovementsView
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
            dgvMovements = new System.Windows.Forms.DataGridView();
            ((System.ComponentModel.ISupportInitialize)dgvMovements).BeginInit();
            SuspendLayout();

            dgvMovements.Dock     = System.Windows.Forms.DockStyle.Fill;
            dgvMovements.Name     = "dgvMovements";
            dgvMovements.TabIndex = 0;

            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(dgvMovements);
            Name = "MovementsView";
            Size = new System.Drawing.Size(1200, 686);

            ((System.ComponentModel.ISupportInitialize)dgvMovements).EndInit();
            ResumeLayout(false);
        }

        private System.Windows.Forms.DataGridView dgvMovements;
    }
}
