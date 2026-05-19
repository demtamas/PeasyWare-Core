namespace PeasyWare.Desktop.Views.Shipments
{
    partial class ShipmentsView
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
                components.Dispose();
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        private void InitializeComponent()
        {
            dgvShipments = new System.Windows.Forms.DataGridView();
            ((System.ComponentModel.ISupportInitialize)dgvShipments).BeginInit();
            SuspendLayout();
            // 
            // dgvShipments
            // 
            dgvShipments.ColumnHeadersHeightSizeMode = System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            dgvShipments.Dock     = System.Windows.Forms.DockStyle.Fill;
            dgvShipments.Location = new System.Drawing.Point(0, 0);
            dgvShipments.Name     = "dgvShipments";
            dgvShipments.Size     = new System.Drawing.Size(1200, 686);
            dgvShipments.TabIndex = 0;
            // 
            // ShipmentsView
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(dgvShipments);
            Name = "ShipmentsView";
            Size = new System.Drawing.Size(1200, 686);
            ((System.ComponentModel.ISupportInitialize)dgvShipments).EndInit();
            ResumeLayout(false);
        }

        #endregion

        private System.Windows.Forms.DataGridView dgvShipments;
    }
}
