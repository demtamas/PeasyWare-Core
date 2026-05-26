namespace PeasyWare.Desktop.Views.Logs;

partial class SkuAuditView
{
    private System.ComponentModel.IContainer components = null;
    private System.Windows.Forms.DataGridView dgvSkuAudit;

    protected override void Dispose(bool disposing)
    {
        if (disposing && components != null) components.Dispose();
        base.Dispose(disposing);
    }

    private void InitializeComponent()
    {
        dgvSkuAudit = new System.Windows.Forms.DataGridView();
        ((System.ComponentModel.ISupportInitialize)dgvSkuAudit).BeginInit();
        SuspendLayout();

        dgvSkuAudit.Dock     = System.Windows.Forms.DockStyle.Fill;
        dgvSkuAudit.Location = new System.Drawing.Point(0, 0);
        dgvSkuAudit.Name     = "dgvSkuAudit";
        dgvSkuAudit.Size     = new System.Drawing.Size(1200, 600);
        dgvSkuAudit.TabIndex = 0;

        AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
        AutoScaleMode       = System.Windows.Forms.AutoScaleMode.Font;
        Controls.Add(dgvSkuAudit);
        Dock = System.Windows.Forms.DockStyle.Fill;
        Name = "SkuAuditView";
        Size = new System.Drawing.Size(1200, 600);

        ((System.ComponentModel.ISupportInitialize)dgvSkuAudit).EndInit();
        ResumeLayout(false);
    }
}
