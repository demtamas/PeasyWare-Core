namespace PeasyWare.Desktop.Forms.Settings
{
    partial class SettingEditForm
    {
        /// <summary>
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary>
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            lblSettingName = new Label();
            lblType = new Label();
            lblDescription = new Label();
            chkValue = new CheckBox();
            txtValue = new TextBox();
            cmbValue = new ComboBox();
            btnSave = new Button();
            btnCancel = new Button();
            numValue = new NumericUpDown();
            ((System.ComponentModel.ISupportInitialize)numValue).BeginInit();
            SuspendLayout();
            // 
            // lblSettingName
            // 
            lblSettingName.AutoSize = true;
            lblSettingName.Location = new Point(93, 99);
            lblSettingName.Name = "lblSettingName";
            lblSettingName.Size = new Size(38, 15);
            lblSettingName.TabIndex = 0;
            lblSettingName.Text = "label1";
            // 
            // lblType
            // 
            lblType.AutoSize = true;
            lblType.Location = new Point(94, 173);
            lblType.Name = "lblType";
            lblType.Size = new Size(38, 15);
            lblType.TabIndex = 0;
            lblType.Text = "label1";
            // 
            // lblDescription
            // 
            lblDescription.AutoSize = true;
            lblDescription.Location = new Point(94, 245);
            lblDescription.Name = "lblDescription";
            lblDescription.Size = new Size(38, 15);
            lblDescription.TabIndex = 0;
            lblDescription.Text = "label1";
            // 
            // chkValue
            // 
            chkValue.AutoSize = true;
            chkValue.Location = new Point(307, 173);
            chkValue.Name = "chkValue";
            chkValue.Size = new Size(82, 19);
            chkValue.TabIndex = 1;
            chkValue.Text = "checkBox1";
            chkValue.UseVisualStyleBackColor = true;
            // 
            // txtValue
            // 
            txtValue.Location = new Point(304, 224);
            txtValue.Name = "txtValue";
            txtValue.Size = new Size(100, 23);
            txtValue.TabIndex = 2;
            // 
            // cmbValue
            // 
            cmbValue.FormattingEnabled = true;
            cmbValue.Location = new Point(308, 291);
            cmbValue.Name = "cmbValue";
            cmbValue.Size = new Size(121, 23);
            cmbValue.TabIndex = 3;
            // 
            // btnSave
            // 
            btnSave.Location = new Point(94, 368);
            btnSave.Name = "btnSave";
            btnSave.Size = new Size(132, 30);
            btnSave.TabIndex = 4;
            btnSave.Text = "&Save";
            btnSave.UseVisualStyleBackColor = true;
            btnSave.Click += btnSave_Click;
            // 
            // btnCancel
            // 
            btnCancel.Location = new Point(297, 368);
            btnCancel.Name = "btnCancel";
            btnCancel.Size = new Size(132, 30);
            btnCancel.TabIndex = 4;
            btnCancel.Text = "&Cancel";
            btnCancel.UseVisualStyleBackColor = true;
            // 
            // numValue
            // 
            numValue.Location = new Point(308, 122);
            numValue.Maximum = new decimal(new int[] { 1000000, 0, 0, 0 });
            numValue.Name = "numValue";
            numValue.Size = new Size(120, 23);
            numValue.TabIndex = 5;
            numValue.Visible = false;
            // 
            // SettingEditForm
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(800, 450);
            ControlBox = false;
            Controls.Add(numValue);
            Controls.Add(btnCancel);
            Controls.Add(btnSave);
            Controls.Add(cmbValue);
            Controls.Add(txtValue);
            Controls.Add(chkValue);
            Controls.Add(lblDescription);
            Controls.Add(lblType);
            Controls.Add(lblSettingName);
            Name = "SettingEditForm";
            StartPosition = FormStartPosition.CenterParent;
            Text = "Edit operational setting";
            ((System.ComponentModel.ISupportInitialize)numValue).EndInit();
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private Label lblSettingName;
        private Label lblType;
        private Label lblDescription;
        private CheckBox chkValue;
        private TextBox txtValue;
        private ComboBox cmbValue;
        private Button btnSave;
        private Button btnCancel;
        private NumericUpDown numValue;
    }
}