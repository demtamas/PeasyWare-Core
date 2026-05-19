namespace PeasyWare.Desktop.Views.Warehouse
{
    partial class TasksView
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
            dgvTasks = new System.Windows.Forms.DataGridView();
            ((System.ComponentModel.ISupportInitialize)dgvTasks).BeginInit();
            SuspendLayout();
            // 
            // dgvTasks
            // 
            dgvTasks.ColumnHeadersHeightSizeMode = System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            dgvTasks.Dock     = System.Windows.Forms.DockStyle.Fill;
            dgvTasks.Location = new System.Drawing.Point(0, 0);
            dgvTasks.Name     = "dgvTasks";
            dgvTasks.Size     = new System.Drawing.Size(1200, 686);
            dgvTasks.TabIndex = 0;
            // 
            // TasksView
            // 
            AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
            AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
            Controls.Add(dgvTasks);
            Name = "TasksView";
            Size = new System.Drawing.Size(1200, 686);
            ((System.ComponentModel.ISupportInitialize)dgvTasks).EndInit();
            ResumeLayout(false);
        }

        #endregion

        private System.Windows.Forms.DataGridView dgvTasks;
    }
}
