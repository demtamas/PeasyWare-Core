namespace PeasyWare.Desktop.Views.Materials;

partial class MaterialsView
{
    private System.ComponentModel.IContainer components = null;
    private System.Windows.Forms.DataGridView dgvMaterials;

    protected override void Dispose(bool disposing)
    {
        if (disposing && (components != null))
            components.Dispose();
        base.Dispose(disposing);
    }

    private void InitializeComponent()
    {
        dgvMaterials = new System.Windows.Forms.DataGridView();
        ((System.ComponentModel.ISupportInitialize)dgvMaterials).BeginInit();
        SuspendLayout();

        dgvMaterials.Dock = System.Windows.Forms.DockStyle.Fill;
        dgvMaterials.Location = new System.Drawing.Point(0, 0);
        dgvMaterials.Name = "dgvMaterials";
        dgvMaterials.Size = new System.Drawing.Size(900, 500);
        dgvMaterials.TabIndex = 0;

        AutoScaleDimensions = new System.Drawing.SizeF(7F, 15F);
        AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
        Controls.Add(dgvMaterials);
        Dock = System.Windows.Forms.DockStyle.Fill;
        Name = "MaterialsView";
        Size = new System.Drawing.Size(900, 500);

        ((System.ComponentModel.ISupportInitialize)dgvMaterials).EndInit();
        ResumeLayout(false);
    }
}
