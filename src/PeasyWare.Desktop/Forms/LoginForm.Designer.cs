namespace PeasyWare.Desktop.Forms
{
    partial class LoginForm
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
            txtPassword = new TextBox();
            label1 = new Label();
            label2 = new Label();
            btnClear = new Button();
            btnLogin = new Button();
            btnExit = new Button();
            lblCapsLock = new Label();
            SuspendLayout();
            // 
            // txtUsername
            // 
            txtUsername.Location = new Point(159, 79);
            txtUsername.Name = "txtUsername";
            txtUsername.Size = new Size(204, 23);
            txtUsername.TabIndex = 0;
            txtUsername.TextChanged += Credentials_TextChanged;
            // 
            // txtPassword
            // 
            txtPassword.Location = new Point(159, 127);
            txtPassword.Name = "txtPassword";
            txtPassword.PasswordChar = '#';
            txtPassword.Size = new Size(204, 23);
            txtPassword.TabIndex = 1;
            txtPassword.TextChanged += Credentials_TextChanged;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new Point(49, 79);
            label1.Name = "label1";
            label1.Size = new Size(69, 15);
            label1.TabIndex = 1;
            label1.Text = "Username : ";
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new Point(49, 127);
            label2.Name = "label2";
            label2.Size = new Size(66, 15);
            label2.TabIndex = 1;
            label2.Text = "Password : ";
            // 
            // btnClear
            // 
            btnClear.Location = new Point(163, 197);
            btnClear.Name = "btnClear";
            btnClear.Size = new Size(75, 23);
            btnClear.TabIndex = 3;
            btnClear.Text = "&Clear";
            btnClear.UseVisualStyleBackColor = true;
            btnClear.Click += btnClear_Click;
            // 
            // btnLogin
            // 
            btnLogin.Location = new Point(43, 197);
            btnLogin.Name = "btnLogin";
            btnLogin.Size = new Size(75, 23);
            btnLogin.TabIndex = 2;
            btnLogin.Text = "&Login";
            btnLogin.UseVisualStyleBackColor = true;
            btnLogin.Click += btnLogin_Click;
            // 
            // btnExit
            // 
            btnExit.Location = new Point(288, 197);
            btnExit.Name = "btnExit";
            btnExit.Size = new Size(75, 23);
            btnExit.TabIndex = 4;
            btnExit.Text = "E&xit";
            btnExit.UseVisualStyleBackColor = true;
            btnExit.Click += btnExit_Click;
            // 
            // lblCapsLock
            // 
            lblCapsLock.AutoSize = true;
            lblCapsLock.ForeColor = Color.Firebrick;
            lblCapsLock.Location = new Point(159, 163);
            lblCapsLock.Name = "lblCapsLock";
            lblCapsLock.Size = new Size(108, 15);
            lblCapsLock.TabIndex = 5;
            lblCapsLock.Text = "⚠ Caps Lock is ON";
            lblCapsLock.Visible = false;
            // 
            // LoginForm
            // 
            AcceptButton = btnLogin;
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            CancelButton = btnExit;
            ClientSize = new Size(434, 261);
            ControlBox = false;
            Controls.Add(lblCapsLock);
            Controls.Add(btnLogin);
            Controls.Add(btnExit);
            Controls.Add(btnClear);
            Controls.Add(label2);
            Controls.Add(label1);
            Controls.Add(txtPassword);
            Controls.Add(txtUsername);
            Name = "LoginForm";
            StartPosition = FormStartPosition.CenterScreen;
            Text = "PeasyWare - Login";
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private TextBox txtUsername;
        private TextBox txtPassword;
        private Label label1;
        private Label label2;
        private Button btnClear;
        private Button btnLogin;
        private Button btnExit;
        private Label lblCapsLock;
    }
}