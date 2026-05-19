namespace PeasyWare.Desktop.Views.Outbound
{
    partial class OutstandingOrdersView
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
            dgvOrders = new System.Windows.Forms.DataGridView();
            ((System.ComponentModel.ISupportInitialize)dgvOrders).BeginInit();
            SuspendLayout();
            // 
            // dgvOrders
            // 
            dgvOrders.ColumnHeadersHeightSizeMode = System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            dgvOrders.Dock     = System.Windows.Forms.DockStyle.Fill;
            dgvOrders.Location = new System.Drawing.Point(0, 0);
            dgvOrders.Name     = "dgvOrders";
            dgvOrders.Size     = new System.Drawing.Size(964, 686);
            dgvOrders.TabIndex = 0;
            // 
            // OutstandingOrdersView
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(dgvOrders);
            Name = "OutstandingOrdersView";
            Size = new System.Drawing.Size(964, 686);
            ((System.ComponentModel.ISupportInitialize)dgvOrders).EndInit();
            ResumeLayout(false);
        }

        #endregion

        private System.Windows.Forms.DataGridView dgvOrders;
    }
}
