namespace PeasyWare.Desktop.Forms
{
    partial class PasswordChangeForm
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
            txtNewPassword = new TextBox();
            txtConfirmPassword = new TextBox();
            label1 = new Label();
            label2 = new Label();
            lblMessage = new Label();
            btnOk = new Button();
            btnCancel = new Button();
            lblCapsLock = new Label();
            lblPasswordHint = new Label();
            SuspendLayout();
            // 
            // txtNewPassword
            // 
            txtNewPassword.Location = new Point(262, 29);
            txtNewPassword.Name = "txtNewPassword";
            txtNewPassword.PasswordChar = '#';
            txtNewPassword.Size = new Size(163, 23);
            txtNewPassword.TabIndex = 0;
            // 
            // txtConfirmPassword
            // 
            txtConfirmPassword.Location = new Point(262, 73);
            txtConfirmPassword.Name = "txtConfirmPassword";
            txtConfirmPassword.PasswordChar = '#';
            txtConfirmPassword.Size = new Size(163, 23);
            txtConfirmPassword.TabIndex = 1;
            // 
            // label1
            // 
            label1.AutoSize = true;
            label1.Location = new Point(39, 37);
            label1.Name = "label1";
            label1.Size = new Size(181, 15);
            label1.TabIndex = 1;
            label1.Text = "Please enter your new password :";
            // 
            // label2
            // 
            label2.AutoSize = true;
            label2.Location = new Point(39, 73);
            label2.Name = "label2";
            label2.Size = new Size(196, 15);
            label2.TabIndex = 1;
            label2.Text = "Please confirm your new password :";
            // 
            // lblMessage
            // 
            lblMessage.AutoSize = true;
            lblMessage.Location = new Point(39, 109);
            lblMessage.Name = "lblMessage";
            lblMessage.Size = new Size(10, 15);
            lblMessage.TabIndex = 2;
            lblMessage.Text = ".";
            // 
            // btnOk
            // 
            btnOk.Location = new Point(241, 155);
            btnOk.Name = "btnOk";
            btnOk.Size = new Size(75, 23);
            btnOk.TabIndex = 2;
            btnOk.Text = "&Update";
            btnOk.UseVisualStyleBackColor = true;
            btnOk.Click += btnOk_Click;
            // 
            // btnCancel
            // 
            btnCancel.Location = new Point(343, 155);
            btnCancel.Name = "btnCancel";
            btnCancel.Size = new Size(75, 23);
            btnCancel.TabIndex = 3;
            btnCancel.Text = "&Cancel";
            btnCancel.UseVisualStyleBackColor = true;
            btnCancel.Click += btnCancel_Click;
            // 
            // lblCapsLock
            // 
            lblCapsLock.AutoSize = true;
            lblCapsLock.ForeColor = Color.Firebrick;
            lblCapsLock.Location = new Point(262, 109);
            lblCapsLock.Name = "lblCapsLock";
            lblCapsLock.Size = new Size(108, 15);
            lblCapsLock.TabIndex = 4;
            lblCapsLock.Text = "⚠ Caps Lock is ON";
            lblCapsLock.Visible = false;
            // 
            // lblPasswordHint
            // 
            lblPasswordHint.AutoSize = true;
            lblPasswordHint.ForeColor = SystemColors.ButtonShadow;
            lblPasswordHint.Location = new Point(262, 55);
            lblPasswordHint.Name = "lblPasswordHint";
            lblPasswordHint.Size = new Size(0, 15);
            lblPasswordHint.TabIndex = 5;
            // 
            // PasswordChangeForm
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(484, 211);
            Controls.Add(lblPasswordHint);
            Controls.Add(lblCapsLock);
            Controls.Add(btnCancel);
            Controls.Add(btnOk);
            Controls.Add(lblMessage);
            Controls.Add(label2);
            Controls.Add(label1);
            Controls.Add(txtConfirmPassword);
            Controls.Add(txtNewPassword);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "PasswordChangeForm";
            StartPosition = FormStartPosition.CenterScreen;
            Text = "You must change your password!";
            ResumeLayout(false);
            PerformLayout();
        }

        #endregion

        private TextBox txtNewPassword;
        private TextBox txtConfirmPassword;
        private Label label1;
        private Label label2;
        private Label lblMessage;
        private Button btnOk;
        private Button btnCancel;
        private Label lblCapsLock;
        private Label lblPasswordHint;
    }
}