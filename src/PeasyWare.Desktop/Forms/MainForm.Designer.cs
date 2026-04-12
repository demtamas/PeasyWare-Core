namespace PeasyWare.Desktop.Forms
{
    partial class MainForm
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
            pnlMenuStrip = new Panel();
            menuStrip1 = new MenuStrip();
            fileToolStripMenuItem = new ToolStripMenuItem();
            switchUserToolStripMenuItem = new ToolStripMenuItem();
            logoutToolStripMenuItem = new ToolStripMenuItem();
            exitToolStripMenuItem = new ToolStripMenuItem();
            inboundToolStripMenuItem = new ToolStripMenuItem();
            inventoryToolStripMenuItem = new ToolStripMenuItem();
            movementsToolStripMenuItem = new ToolStripMenuItem();
            countingToolStripMenuItem = new ToolStripMenuItem();
            oToolStripMenuItem = new ToolStripMenuItem();
            adminToolStripMenuItem = new ToolStripMenuItem();
            usersToolStripMenuItem = new ToolStripMenuItem();
            sessionsToolStripMenuItem = new ToolStripMenuItem();
            sessionEventsToolStripMenuItem = new ToolStripMenuItem();
            rolesAndPermissionsToolStripMenuItem = new ToolStripMenuItem();
            locationsToolStripMenuItem = new ToolStripMenuItem();
            materialsToolStripMenuItem = new ToolStripMenuItem();
            suppliersToolStripMenuItem = new ToolStripMenuItem();
            customersToolStripMenuItem = new ToolStripMenuItem();
            systemToolStripMenuItem = new ToolStripMenuItem();
            sToolStripMenuItem = new ToolStripMenuItem();
            operationalSettingsToolStripMenuItem = new ToolStripMenuItem();
            clientSettingsToolStripMenuItem = new ToolStripMenuItem();
            logsToolStripMenuItem = new ToolStripMenuItem();
            loginAttemptsToolStripMenuItem = new ToolStripMenuItem();
            userChangesToolStripMenuItem = new ToolStripMenuItem();
            helpToolStripMenuItem = new ToolStripMenuItem();
            aboutPeasyWareToolStripMenuItem = new ToolStripMenuItem();
            versionInfoToolStripMenuItem = new ToolStripMenuItem();
            databaseVersionToolStripMenuItem = new ToolStripMenuItem();
            supportToolStripMenuItem = new ToolStripMenuItem();
            pnlToolStrip = new Panel();
            mainToolStrip = new ToolStrip();
            pnlStatusStrip = new Panel();
            statusStrip1 = new StatusStrip();
            toolStripStatusLabel1 = new ToolStripStatusLabel();
            pnlMain = new Panel();
            pnlMenuStrip.SuspendLayout();
            menuStrip1.SuspendLayout();
            pnlToolStrip.SuspendLayout();
            pnlStatusStrip.SuspendLayout();
            statusStrip1.SuspendLayout();
            SuspendLayout();
            // 
            // pnlMenuStrip
            // 
            pnlMenuStrip.Controls.Add(menuStrip1);
            pnlMenuStrip.Dock = DockStyle.Top;
            pnlMenuStrip.Location = new Point(0, 0);
            pnlMenuStrip.Name = "pnlMenuStrip";
            pnlMenuStrip.Size = new Size(1384, 26);
            pnlMenuStrip.TabIndex = 0;
            // 
            // menuStrip1
            // 
            menuStrip1.Items.AddRange(new ToolStripItem[] { fileToolStripMenuItem, inboundToolStripMenuItem, inventoryToolStripMenuItem, movementsToolStripMenuItem, countingToolStripMenuItem, oToolStripMenuItem, adminToolStripMenuItem, systemToolStripMenuItem, helpToolStripMenuItem });
            menuStrip1.Location = new Point(0, 0);
            menuStrip1.Name = "menuStrip1";
            menuStrip1.Size = new Size(1384, 24);
            menuStrip1.TabIndex = 0;
            menuStrip1.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            fileToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { switchUserToolStripMenuItem, logoutToolStripMenuItem, exitToolStripMenuItem });
            fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            fileToolStripMenuItem.Size = new Size(37, 20);
            fileToolStripMenuItem.Text = "&File";
            // 
            // switchUserToolStripMenuItem
            // 
            switchUserToolStripMenuItem.Name = "switchUserToolStripMenuItem";
            switchUserToolStripMenuItem.Size = new Size(134, 22);
            switchUserToolStripMenuItem.Text = "S&witch user";
            // 
            // logoutToolStripMenuItem
            // 
            logoutToolStripMenuItem.Name = "logoutToolStripMenuItem";
            logoutToolStripMenuItem.Size = new Size(134, 22);
            logoutToolStripMenuItem.Text = "Logou&t";
            logoutToolStripMenuItem.Click += logoutToolStripMenuItem_Click;
            // 
            // exitToolStripMenuItem
            // 
            exitToolStripMenuItem.Name = "exitToolStripMenuItem";
            exitToolStripMenuItem.Size = new Size(134, 22);
            exitToolStripMenuItem.Text = "E&xit";
            exitToolStripMenuItem.Click += exitToolStripMenuItem_Click;
            // 
            // inboundToolStripMenuItem
            // 
            inboundToolStripMenuItem.Name = "inboundToolStripMenuItem";
            inboundToolStripMenuItem.Size = new Size(64, 20);
            inboundToolStripMenuItem.Text = "&Inbound";
            // 
            // inventoryToolStripMenuItem
            // 
            inventoryToolStripMenuItem.Name = "inventoryToolStripMenuItem";
            inventoryToolStripMenuItem.Size = new Size(69, 20);
            inventoryToolStripMenuItem.Text = "In&ventory";
            // 
            // movementsToolStripMenuItem
            // 
            movementsToolStripMenuItem.Name = "movementsToolStripMenuItem";
            movementsToolStripMenuItem.Size = new Size(82, 20);
            movementsToolStripMenuItem.Text = "&Movements";
            // 
            // countingToolStripMenuItem
            // 
            countingToolStripMenuItem.Name = "countingToolStripMenuItem";
            countingToolStripMenuItem.Size = new Size(69, 20);
            countingToolStripMenuItem.Text = "&Counting";
            // 
            // oToolStripMenuItem
            // 
            oToolStripMenuItem.Name = "oToolStripMenuItem";
            oToolStripMenuItem.Size = new Size(74, 20);
            oToolStripMenuItem.Text = "&Outbound";
            // 
            // adminToolStripMenuItem
            // 
            adminToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { usersToolStripMenuItem, sessionsToolStripMenuItem, sessionEventsToolStripMenuItem, rolesAndPermissionsToolStripMenuItem, locationsToolStripMenuItem, materialsToolStripMenuItem, suppliersToolStripMenuItem, customersToolStripMenuItem });
            adminToolStripMenuItem.Name = "adminToolStripMenuItem";
            adminToolStripMenuItem.Size = new Size(55, 20);
            adminToolStripMenuItem.Text = "&Admin";
            // 
            // usersToolStripMenuItem
            // 
            usersToolStripMenuItem.Name = "usersToolStripMenuItem";
            usersToolStripMenuItem.Size = new Size(191, 22);
            usersToolStripMenuItem.Text = "&Users";
            usersToolStripMenuItem.Click += usersToolStripMenuItem_Click;
            // 
            // sessionsToolStripMenuItem
            // 
            sessionsToolStripMenuItem.Name = "sessionsToolStripMenuItem";
            sessionsToolStripMenuItem.Size = new Size(191, 22);
            sessionsToolStripMenuItem.Text = "&Sessions";
            sessionsToolStripMenuItem.Click += sessionsToolStripMenuItem_Click;
            // 
            // sessionEventsToolStripMenuItem
            // 
            sessionEventsToolStripMenuItem.Name = "sessionEventsToolStripMenuItem";
            sessionEventsToolStripMenuItem.Size = new Size(191, 22);
            sessionEventsToolStripMenuItem.Text = "Session Events";
            // 
            // rolesAndPermissionsToolStripMenuItem
            // 
            rolesAndPermissionsToolStripMenuItem.Name = "rolesAndPermissionsToolStripMenuItem";
            rolesAndPermissionsToolStripMenuItem.Size = new Size(191, 22);
            rolesAndPermissionsToolStripMenuItem.Text = "&Roles and permissions";
            // 
            // locationsToolStripMenuItem
            // 
            locationsToolStripMenuItem.Name = "locationsToolStripMenuItem";
            locationsToolStripMenuItem.Size = new Size(191, 22);
            locationsToolStripMenuItem.Text = "&Locations";
            // 
            // materialsToolStripMenuItem
            // 
            materialsToolStripMenuItem.Name = "materialsToolStripMenuItem";
            materialsToolStripMenuItem.Size = new Size(191, 22);
            materialsToolStripMenuItem.Text = "&Materials";
            // 
            // suppliersToolStripMenuItem
            // 
            suppliersToolStripMenuItem.Name = "suppliersToolStripMenuItem";
            suppliersToolStripMenuItem.Size = new Size(191, 22);
            suppliersToolStripMenuItem.Text = "Su&ppliers";
            // 
            // customersToolStripMenuItem
            // 
            customersToolStripMenuItem.Name = "customersToolStripMenuItem";
            customersToolStripMenuItem.Size = new Size(191, 22);
            customersToolStripMenuItem.Text = "&Customers";
            // 
            // systemToolStripMenuItem
            // 
            systemToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { sToolStripMenuItem, logsToolStripMenuItem });
            systemToolStripMenuItem.Name = "systemToolStripMenuItem";
            systemToolStripMenuItem.Size = new Size(57, 20);
            systemToolStripMenuItem.Text = "&System";
            // 
            // sToolStripMenuItem
            // 
            sToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { operationalSettingsToolStripMenuItem, clientSettingsToolStripMenuItem });
            sToolStripMenuItem.Name = "sToolStripMenuItem";
            sToolStripMenuItem.Size = new Size(116, 22);
            sToolStripMenuItem.Text = "S&ettings";
            // 
            // operationalSettingsToolStripMenuItem
            // 
            operationalSettingsToolStripMenuItem.Name = "operationalSettingsToolStripMenuItem";
            operationalSettingsToolStripMenuItem.Size = new Size(180, 22);
            operationalSettingsToolStripMenuItem.Text = "&Operational settings";
            operationalSettingsToolStripMenuItem.Click += operationalSettingsToolStripMenuItem_Click;
            // 
            // clientSettingsToolStripMenuItem
            // 
            clientSettingsToolStripMenuItem.Name = "clientSettingsToolStripMenuItem";
            clientSettingsToolStripMenuItem.Size = new Size(180, 22);
            clientSettingsToolStripMenuItem.Text = "Client settin&gs";
            // 
            // logsToolStripMenuItem
            // 
            logsToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { loginAttemptsToolStripMenuItem, userChangesToolStripMenuItem });
            logsToolStripMenuItem.Name = "logsToolStripMenuItem";
            logsToolStripMenuItem.Size = new Size(116, 22);
            logsToolStripMenuItem.Text = "&Logs";
            // 
            // loginAttemptsToolStripMenuItem
            // 
            loginAttemptsToolStripMenuItem.Name = "loginAttemptsToolStripMenuItem";
            loginAttemptsToolStripMenuItem.Size = new Size(156, 22);
            loginAttemptsToolStripMenuItem.Text = "Login &Attempts";
            // 
            // userChangesToolStripMenuItem
            // 
            userChangesToolStripMenuItem.Name = "userChangesToolStripMenuItem";
            userChangesToolStripMenuItem.Size = new Size(156, 22);
            userChangesToolStripMenuItem.Text = "&User changes";
            // 
            // helpToolStripMenuItem
            // 
            helpToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { aboutPeasyWareToolStripMenuItem, versionInfoToolStripMenuItem, databaseVersionToolStripMenuItem, supportToolStripMenuItem });
            helpToolStripMenuItem.Name = "helpToolStripMenuItem";
            helpToolStripMenuItem.Size = new Size(44, 20);
            helpToolStripMenuItem.Text = "&Help";
            // 
            // aboutPeasyWareToolStripMenuItem
            // 
            aboutPeasyWareToolStripMenuItem.Name = "aboutPeasyWareToolStripMenuItem";
            aboutPeasyWareToolStripMenuItem.Size = new Size(167, 22);
            aboutPeasyWareToolStripMenuItem.Text = "&About PeasyWare";
            // 
            // versionInfoToolStripMenuItem
            // 
            versionInfoToolStripMenuItem.Name = "versionInfoToolStripMenuItem";
            versionInfoToolStripMenuItem.Size = new Size(167, 22);
            versionInfoToolStripMenuItem.Text = "&Version info";
            // 
            // databaseVersionToolStripMenuItem
            // 
            databaseVersionToolStripMenuItem.Name = "databaseVersionToolStripMenuItem";
            databaseVersionToolStripMenuItem.Size = new Size(167, 22);
            databaseVersionToolStripMenuItem.Text = "&Database version";
            // 
            // supportToolStripMenuItem
            // 
            supportToolStripMenuItem.Name = "supportToolStripMenuItem";
            supportToolStripMenuItem.Size = new Size(167, 22);
            supportToolStripMenuItem.Text = "Su&pport";
            // 
            // pnlToolStrip
            // 
            pnlToolStrip.Controls.Add(mainToolStrip);
            pnlToolStrip.Dock = DockStyle.Top;
            pnlToolStrip.Location = new Point(0, 26);
            pnlToolStrip.Name = "pnlToolStrip";
            pnlToolStrip.Size = new Size(1384, 36);
            pnlToolStrip.TabIndex = 1;
            // 
            // mainToolStrip
            // 
            mainToolStrip.Dock = DockStyle.Fill;
            mainToolStrip.Location = new Point(0, 0);
            mainToolStrip.Name = "mainToolStrip";
            mainToolStrip.Size = new Size(1384, 36);
            mainToolStrip.TabIndex = 0;
            mainToolStrip.Text = "toolStrip1";
            // 
            // pnlStatusStrip
            // 
            pnlStatusStrip.Controls.Add(statusStrip1);
            pnlStatusStrip.Dock = DockStyle.Bottom;
            pnlStatusStrip.Location = new Point(0, 737);
            pnlStatusStrip.Name = "pnlStatusStrip";
            pnlStatusStrip.Size = new Size(1384, 24);
            pnlStatusStrip.TabIndex = 2;
            // 
            // statusStrip1
            // 
            statusStrip1.Dock = DockStyle.Fill;
            statusStrip1.Items.AddRange(new ToolStripItem[] { toolStripStatusLabel1 });
            statusStrip1.Location = new Point(0, 0);
            statusStrip1.Name = "statusStrip1";
            statusStrip1.Size = new Size(1384, 24);
            statusStrip1.TabIndex = 0;
            statusStrip1.Text = "statusStrip1";
            // 
            // toolStripStatusLabel1
            // 
            toolStripStatusLabel1.Name = "toolStripStatusLabel1";
            toolStripStatusLabel1.Size = new Size(139, 19);
            toolStripStatusLabel1.Text = "toolStripStatusLabelMain";
            // 
            // pnlMain
            // 
            pnlMain.Dock = DockStyle.Fill;
            pnlMain.Location = new Point(0, 62);
            pnlMain.Name = "pnlMain";
            pnlMain.Padding = new Padding(8);
            pnlMain.Size = new Size(1384, 675);
            pnlMain.TabIndex = 3;
            // 
            // MainForm
            // 
            AutoScaleDimensions = new SizeF(7F, 15F);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(1384, 761);
            ControlBox = false;
            Controls.Add(pnlMain);
            Controls.Add(pnlStatusStrip);
            Controls.Add(pnlToolStrip);
            Controls.Add(pnlMenuStrip);
            MainMenuStrip = menuStrip1;
            Name = "MainForm";
            Text = "PeasyWare";
            WindowState = FormWindowState.Maximized;
            pnlMenuStrip.ResumeLayout(false);
            pnlMenuStrip.PerformLayout();
            menuStrip1.ResumeLayout(false);
            menuStrip1.PerformLayout();
            pnlToolStrip.ResumeLayout(false);
            pnlToolStrip.PerformLayout();
            pnlStatusStrip.ResumeLayout(false);
            pnlStatusStrip.PerformLayout();
            statusStrip1.ResumeLayout(false);
            statusStrip1.PerformLayout();
            ResumeLayout(false);
        }

        #endregion

        private Panel pnlMenuStrip;
        private Panel pnlToolStrip;
        private Panel pnlStatusStrip;
        private Panel pnlMain;
        private MenuStrip menuStrip1;
        private ToolStripMenuItem fileToolStripMenuItem;
        private ToolStripMenuItem switchUserToolStripMenuItem;
        private ToolStripMenuItem logoutToolStripMenuItem;
        private ToolStripMenuItem exitToolStripMenuItem;
        private ToolStripMenuItem inboundToolStripMenuItem;
        private ToolStripMenuItem inventoryToolStripMenuItem;
        private ToolStripMenuItem movementsToolStripMenuItem;
        private ToolStripMenuItem countingToolStripMenuItem;
        private ToolStripMenuItem oToolStripMenuItem;
        private ToolStripMenuItem adminToolStripMenuItem;
        private ToolStripMenuItem systemToolStripMenuItem;
        private ToolStripMenuItem helpToolStripMenuItem;
        private ToolStripMenuItem aboutPeasyWareToolStripMenuItem;
        private ToolStripMenuItem versionInfoToolStripMenuItem;
        private ToolStripMenuItem databaseVersionToolStripMenuItem;
        private ToolStripMenuItem supportToolStripMenuItem;
        private ToolStripMenuItem usersToolStripMenuItem;
        private ToolStripMenuItem sessionsToolStripMenuItem;
        private ToolStripMenuItem rolesAndPermissionsToolStripMenuItem;
        private ToolStripMenuItem locationsToolStripMenuItem;
        private ToolStripMenuItem materialsToolStripMenuItem;
        private ToolStripMenuItem suppliersToolStripMenuItem;
        private ToolStripMenuItem customersToolStripMenuItem;
        private ToolStripMenuItem sToolStripMenuItem;
        private ToolStripMenuItem sessionEventsToolStripMenuItem;
        private ToolStrip mainToolStrip;
        private ToolStripMenuItem logsToolStripMenuItem;
        private ToolStripMenuItem loginAttemptsToolStripMenuItem;
        private ToolStripMenuItem userChangesToolStripMenuItem;
        private ToolStripMenuItem operationalSettingsToolStripMenuItem;
        private ToolStripMenuItem clientSettingsToolStripMenuItem;
        private StatusStrip statusStrip1;
        private ToolStripStatusLabel toolStripStatusLabel1;
    }
}