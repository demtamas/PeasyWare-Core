namespace PeasyWare.Desktop.Views.Users
{
    partial class AddUserForm
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
            txtUsername = new TextBox();
            txtDisplayName = new TextBox();
            txtEmail = new TextBox();
            cmbRole = new ComboBox();
            label1 = new Label();
            label2 = new Label();
            label3 = new Label();
            label4 = new Label();
            label5 = new Label();
            btnSave = new Button();
            btnCancel = new Button();
            txtPassword = new TextBox();
            txtConfirmPassword = new TextBox();
            label6 = new Label();
            btnClear = new Button();
            SuspendLayout();
            // 
            // txtUsername
            // 
            txtUsername.Location = new Point(268, 65);
            txtUsername.Name = "txtUsername";
            txtUsername.Size = new Size(323, 23);
            txtUsername.TabIndex = 0;
            // 
            // txtDisplayName
            // 
            txtDisplayName.Location = new Point(268, 115);
            txtDisplayName.Name = "txtDisplayName";
            txtDisplayName.Size = new Size(323, 23);
            txtDisplayName.TabIndex = 1;
            // 
            // txtEmail
            // 
            txtEmail.Location = new Point(268, 165);
            txtEmail.Name = "txtEmail";
            txtEmail.Size = new Size(323, 23);
            txtEmail.TabIndex = 2;
            // 
            // cmbRole
            // 
            cmbRole.FormattingEnabled = true;
            cmbRole.Location = new Point(268, 215);
            cmbRole.Name = "cmbRole";
            cmbRole.Size = new Size(323, 23);
            cmbRole.TabIndex = 3;
            this.cmbRole.SelectedIndexChanged += new System.EventHandler(this.ValidateInput);
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new Point(130, 73);
            label1.Name = "label1";
            label1.Size = new Size(60, 15);
            label1.TabIndex = 3;
            label1.Text = "Username";
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new Point(130, 123);
            label2.Name = "label2";
            label2.Size = new Size(59, 15);
            label2.TabIndex = 3;
            label2.Text = "Full name";
            // 
            // label3
            // 
            label3.AutoSize = true;
            label3.Location = new Point(130, 177);
            label3.Name = "label3";
            label3.Size = new Size(79, 15);
            label3.TabIndex = 3;
            label3.Text = "Email address";
            // 
            // label4
            // 
            label4.AutoSize = true;
            label4.Location = new Point(130, 223);
            label4.Name = "label4";
            label4.Size = new Size(53, 15);
            label4.TabIndex = 3;
            label4.Text = "User role";
            // 
            // label5
            // 
            label5.AutoSize = true;
            label5.Location = new Point(130, 273);
            label5.Name = "label5";
            label5.Size = new Size(57, 15);
            label5.TabIndex = 3;
            label5.Text = "Password";
            // 
            // btnSave
            // 
            btnSave.Location = new Point(130, 383);
            btnSave.Name = "btnSave";
            btnSave.Size = new Size(122, 23);
            btnSave.TabIndex = 6;
            btnSave.Text = "&Add user";
            btnSave.UseVisualStyleBackColor = true;
            btnSave.Click += btnSave_Click;
            // 
            // btnCancel
            // 
            btnCancel.Location = new Point(469, 383);
            btnCancel.Name = "btnCancel";
            btnCancel.Size = new Size(122, 23);
            btnCancel.TabIndex = 8;
            btnCancel.Text = "&Cancel";
            btnCancel.UseVisualStyleBackColor = true;
            btnCancel.Click += btnCancel_Click;
            // 
            // txtPassword
            // 
            txtPassword.Location = new Point(268, 265);
            txtPassword.Name = "txtPassword";
            txtPassword.Size = new Size(323, 23);
            txtPassword.TabIndex = 4;
            // 
            // txtConfirmPassword
            // 
            txtConfirmPassword.Location = new Point(268, 315);
            txtConfirmPassword.Name = "txtConfirmPassword";
            txtConfirmPassword.Size = new Size(323, 23);
            txtConfirmPassword.TabIndex = 5;
            // 
            // label6
            // 
            label6.AutoSize = true;
            label6.Location = new Point(130, 323);
            label6.Name = "label6";
            label6.Size = new Size(104, 15);
            label6.TabIndex = 3;
            label6.Text = "Confirm password";
            // 
            // btnClear
            // 
            btnClear.Location = new Point(304, 383);
            btnClear.Name = "btnClear";
            btnClear.Size = new Size(122, 23);
            btnClear.TabIndex = 7;
            btnClear.Text = "C&lear";
            btnClear.UseVisualStyleBackColor = true;
            btnClear.Click += btnClear_Click;
            // 
            // AddUserForm
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(800, 450);
            ControlBox = false;
            Controls.Add(btnClear);
            Controls.Add(btnCancel);
            Controls.Add(btnSave);
            Controls.Add(label6);
            Controls.Add(label5);
            Controls.Add(label4);
            Controls.Add(label3);
            Controls.Add(label2);
            Controls.Add(label1);
            Controls.Add(cmbRole);
            Controls.Add(txtConfirmPassword);
            Controls.Add(txtPassword);
            Controls.Add(txtEmail);
            Controls.Add(txtDisplayName);
            Controls.Add(txtUsername);
            Name = "AddUserForm";
            StartPosition = FormStartPosition.CenterParent;
            Text = "AddUserForm";
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private TextBox txtUsername;
        private TextBox txtDisplayName;
        private TextBox txtEmail;
        private ComboBox cmbRole;
        private Label label1;
        private Label label2;
        private Label label3;
        private Label label4;
        private Label label5;
        private Button btnSave;
        private Button btnClear;
        private Button btnCancel;
        private TextBox txtPassword;
        private TextBox txtConfirmPassword;
        private Label label6;
    }
}