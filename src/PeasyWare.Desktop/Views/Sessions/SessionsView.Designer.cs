namespace PeasyWare.Desktop.Views.Sessions
{
    partial class SessionsView
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

        #region Component Designer generated code

        /// <summary> 
        /// Required method for Designer support - do not modify 
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            dgvSessions = new DataGridView();
            SessionId = new DataGridViewTextBoxColumn();
            Username = new DataGridViewTextBoxColumn();
            ClientApp = new DataGridViewTextBoxColumn();
            ClientInfo = new DataGridViewTextBoxColumn();
            LastSeen = new DataGridViewTextBoxColumn();
            IsActive = new DataGridViewButtonColumn();
            ((System.ComponentModel.ISupportInitialize)dgvSessions).BeginInit();
            SuspendLayout();
            // 
            // dgvSessions
            // 
            dgvSessions.AllowUserToAddRows = false;
            dgvSessions.AllowUserToDeleteRows = false;
            dgvSessions.AllowUserToOrderColumns = true;
            dgvSessions.ColumnHeadersHeightSizeMode = DataGridViewColumnHeadersHeightSizeMode.AutoSize;
            dgvSessions.Columns.AddRange(new DataGridViewColumn[] { SessionId, Username, ClientApp, ClientInfo, LastSeen, IsActive });
            dgvSessions.Dock = DockStyle.Fill;
            dgvSessions.Location = new Point(0, 0);
            dgvSessions.Name = "dgvSessions";
            dgvSessions.ReadOnly = true;
            dgvSessions.Size = new Size(776, 487);
            dgvSessions.TabIndex = 0;
            // 
            // SessionId
            // 
            SessionId.DataPropertyName = "SessionId";
            SessionId.HeaderText = "Session ID";
            SessionId.Name = "SessionId";
            SessionId.ReadOnly = true;
            // 
            // Username
            // 
            Username.DataPropertyName = "Username";
            Username.HeaderText = "User";
            Username.Name = "Username";
            Username.ReadOnly = true;
            // 
            // ClientApp
            // 
            ClientApp.DataPropertyName = "ClientApp";
            ClientApp.HeaderText = "Client App";
            ClientApp.Name = "ClientApp";
            ClientApp.ReadOnly = true;
            // 
            // ClientInfo
            // 
            ClientInfo.DataPropertyName = "ClientInfo";
            ClientInfo.HeaderText = "Client Info";
            ClientInfo.Name = "ClientInfo";
            ClientInfo.ReadOnly = true;
            // 
            // LastSeen
            // 
            LastSeen.DataPropertyName = "LastSeen";
            LastSeen.HeaderText = "Last seen";
            LastSeen.Name = "LastSeen";
            LastSeen.ReadOnly = true;
            // 
            // IsActive
            // 
            IsActive.DataPropertyName = "IsActive";
            IsActive.HeaderText = "Active";
            IsActive.Name = "IsActive";
            IsActive.ReadOnly = true;
            IsActive.Resizable = DataGridViewTriState.True;
            IsActive.SortMode = DataGridViewColumnSortMode.Automatic;
            // 
            // SessionsView
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            Controls.Add(dgvSessions);
            Name = "SessionsView";
            Size = new Size(776, 487);
            ((System.ComponentModel.ISupportInitialize)dgvSessions).EndInit();
            ResumeLayout(false);
        }

        #endregion

        private DataGridView dgvSessions;
        private DataGridViewTextBoxColumn SessionId;
        private DataGridViewTextBoxColumn Username;
        private DataGridViewTextBoxColumn ClientApp;
        private DataGridViewTextBoxColumn ClientInfo;
        private DataGridViewTextBoxColumn LastSeen;
        private DataGridViewButtonColumn IsActive;
    }
}
