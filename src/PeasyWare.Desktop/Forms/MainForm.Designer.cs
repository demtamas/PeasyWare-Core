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
            inventoryActiveToolStripMenuItem = new ToolStripMenuItem();
            materialsToolStripMenuItem = new ToolStripMenuItem();
            movementsToolStripMenuItem = new ToolStripMenuItem();
            countingToolStripMenuItem = new ToolStripMenuItem();
            shipmentsToolStripMenuItem = new ToolStripMenuItem();
            outstandingToolStripMenuItem = new ToolStripMenuItem();
            departedToolStripMenuItem1 = new ToolStripMenuItem();
            allToolStripMenuItem1 = new ToolStripMenuItem();
            oToolStripMenuItem = new ToolStripMenuItem();
            outstandiToolStripMenuItem = new ToolStripMenuItem();
            departedToolStripMenuItem = new ToolStripMenuItem();
            allToolStripMenuItem = new ToolStripMenuItem();
            suppliersToolStripMenuItem = new ToolStripMenuItem();
            customersToolStripMenuItem = new ToolStripMenuItem();
            partiesToolStripMenuItem = new ToolStripMenuItem();
            allPartiesToolStripMenuItem = new ToolStripMenuItem();
            suppliersPartiesMenuItem = new ToolStripMenuItem();
            customersPartiesMenuItem = new ToolStripMenuItem();
            hauliersPartiesMenuItem = new ToolStripMenuItem();
            ownersPartiesMenuItem = new ToolStripMenuItem();
            adminToolStripMenuItem = new ToolStripMenuItem();
            usersToolStripMenuItem = new ToolStripMenuItem();
            sessionsToolStripMenuItem = new ToolStripMenuItem();
            sessionEventsToolStripMenuItem = new ToolStripMenuItem();
            rolesAndPermissionsToolStripMenuItem = new ToolStripMenuItem();
            locationsToolStripMenuItem = new ToolStripMenuItem();
            zonesToolStripMenuItem = new ToolStripMenuItem();
            sectionsToolStripMenuItem = new ToolStripMenuItem();
            suppliersToolStripMenuItem = new ToolStripMenuItem();
            customersToolStripMenuItem = new ToolStripMenuItem();
            systemToolStripMenuItem = new ToolStripMenuItem();
            sToolStripMenuItem = new ToolStripMenuItem();
            operationalSettingsToolStripMenuItem = new ToolStripMenuItem();
            clientSettingsToolStripMenuItem = new ToolStripMenuItem();
            logsToolStripMenuItem = new ToolStripMenuItem();
            allEventsToolStripMenuItem = new ToolStripMenuItem();
            loginAttemptsToolStripMenuItem = new ToolStripMenuItem();
            userChangesToolStripMenuItem = new ToolStripMenuItem();
            locationChangesToolStripMenuItem = new ToolStripMenuItem();
            skuChangesToolStripMenuItem = new ToolStripMenuItem();
            warehouseToolStripMenuItem = new ToolStripMenuItem();
            warehouseTasksToolStripMenuItem = new ToolStripMenuItem();
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
            menuStrip1.Items.AddRange(new ToolStripItem[] { fileToolStripMenuItem, inboundToolStripMenuItem, inventoryToolStripMenuItem, movementsToolStripMenuItem, countingToolStripMenuItem, shipmentsToolStripMenuItem, oToolStripMenuItem, warehouseToolStripMenuItem, partiesToolStripMenuItem, adminToolStripMenuItem, systemToolStripMenuItem, helpToolStripMenuItem });
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
            inboundToolStripMenuItem.Click += inboundToolStripMenuItem_Click;
            // 
            // inventoryToolStripMenuItem
            // 
            inventoryToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { inventoryActiveToolStripMenuItem, materialsToolStripMenuItem });
            inventoryToolStripMenuItem.Name = "inventoryToolStripMenuItem";
            inventoryToolStripMenuItem.Size = new Size(69, 20);
            inventoryToolStripMenuItem.Text = "In&ventory";
            // 
            // inventoryActiveToolStripMenuItem
            // 
            inventoryActiveToolStripMenuItem.Name = "inventoryActiveToolStripMenuItem";
            inventoryActiveToolStripMenuItem.Size = new Size(168, 22);
            inventoryActiveToolStripMenuItem.Text = "&Inventory (Active)";
            inventoryActiveToolStripMenuItem.Click += inventoryActiveToolStripMenuItem_Click;
            // 
            // materialsToolStripMenuItem
            // 
            materialsToolStripMenuItem.Name = "materialsToolStripMenuItem";
            materialsToolStripMenuItem.Size = new Size(168, 22);
            materialsToolStripMenuItem.Text = "&Materials";
            materialsToolStripMenuItem.Click += materialsToolStripMenuItem_Click;
            // 
            // movementsToolStripMenuItem
            // 
            movementsToolStripMenuItem.Name = "movementsToolStripMenuItem";
            movementsToolStripMenuItem.Size = new Size(82, 20);
            movementsToolStripMenuItem.Text = "&Movements";
            movementsToolStripMenuItem.Click += movementsToolStripMenuItem_Click;
            // 
            // countingToolStripMenuItem
            // 
            countingToolStripMenuItem.Name = "countingToolStripMenuItem";
            countingToolStripMenuItem.Size = new Size(69, 20);
            countingToolStripMenuItem.Text = "&Counting";
            // 
            // shipmentsToolStripMenuItem
            // 
            shipmentsToolStripMenuItem.Name = "shipmentsToolStripMenuItem";
            shipmentsToolStripMenuItem.Size = new Size(75, 20);
            shipmentsToolStripMenuItem.Text = "Sh&ipments";
            shipmentsToolStripMenuItem.Click += shipmentsToolStripMenuItem_Click;
            // 
            // outstandingToolStripMenuItem
            // 
            outstandingToolStripMenuItem.Name = "outstandingToolStripMenuItem";
            outstandingToolStripMenuItem.Size = new Size(140, 22);
            outstandingToolStripMenuItem.Text = "&Outstanding";
            // 
            // departedToolStripMenuItem1
            // 
            departedToolStripMenuItem1.Name = "departedToolStripMenuItem1";
            departedToolStripMenuItem1.Size = new Size(140, 22);
            departedToolStripMenuItem1.Text = "&Departed";
            // 
            // allToolStripMenuItem1
            // 
            allToolStripMenuItem1.Name = "allToolStripMenuItem1";
            allToolStripMenuItem1.Size = new Size(140, 22);
            allToolStripMenuItem1.Text = "&All";
            // 
            // oToolStripMenuItem
            // 
            oToolStripMenuItem.Name = "oToolStripMenuItem";
            oToolStripMenuItem.Size = new Size(79, 20);
            oToolStripMenuItem.Text = "&Outbounds";
            oToolStripMenuItem.Click += outstandiToolStripMenuItem_Click;
            // 
            // outstandiToolStripMenuItem
            // 
            outstandiToolStripMenuItem.Name = "outstandiToolStripMenuItem";
            outstandiToolStripMenuItem.Size = new Size(180, 22);
            outstandiToolStripMenuItem.Text = "&Outstanding";
            outstandiToolStripMenuItem.Click += outstandiToolStripMenuItem_Click;
            // 
            // departedToolStripMenuItem
            // 
            departedToolStripMenuItem.Name = "departedToolStripMenuItem";
            departedToolStripMenuItem.Size = new Size(180, 22);
            departedToolStripMenuItem.Text = "&Departed";
            // 
            // allToolStripMenuItem
            // 
            allToolStripMenuItem.Name = "allToolStripMenuItem";
            allToolStripMenuItem.Size = new Size(180, 22);
            allToolStripMenuItem.Text = "&All";
            // 
            // partiesToolStripMenuItem
            // 
            partiesToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { allPartiesToolStripMenuItem, suppliersPartiesMenuItem, customersPartiesMenuItem, hauliersPartiesMenuItem, ownersPartiesMenuItem });
            partiesToolStripMenuItem.Name = "partiesToolStripMenuItem";
            partiesToolStripMenuItem.Size = new Size(58, 20);
            partiesToolStripMenuItem.Text = "&Parties";
            // 
            // allPartiesToolStripMenuItem
            // 
            allPartiesToolStripMenuItem.Name = "allPartiesToolStripMenuItem";
            allPartiesToolStripMenuItem.Size = new Size(140, 22);
            allPartiesToolStripMenuItem.Text = "&All parties";
            allPartiesToolStripMenuItem.Click += allPartiesToolStripMenuItem_Click;
            // 
            // suppliersPartiesMenuItem
            // 
            suppliersPartiesMenuItem.Name = "suppliersPartiesMenuItem";
            suppliersPartiesMenuItem.Size = new Size(140, 22);
            suppliersPartiesMenuItem.Text = "&Suppliers";
            suppliersPartiesMenuItem.Click += suppliersPartiesMenuItem_Click;
            // 
            // customersPartiesMenuItem
            // 
            customersPartiesMenuItem.Name = "customersPartiesMenuItem";
            customersPartiesMenuItem.Size = new Size(140, 22);
            customersPartiesMenuItem.Text = "&Customers";
            customersPartiesMenuItem.Click += customersPartiesMenuItem_Click;
            // 
            // hauliersPartiesMenuItem
            // 
            hauliersPartiesMenuItem.Name = "hauliersPartiesMenuItem";
            hauliersPartiesMenuItem.Size = new Size(140, 22);
            hauliersPartiesMenuItem.Text = "&Hauliers";
            hauliersPartiesMenuItem.Click += hauliersPartiesMenuItem_Click;
            // 
            // ownersPartiesMenuItem
            // 
            ownersPartiesMenuItem.Name = "ownersPartiesMenuItem";
            ownersPartiesMenuItem.Size = new Size(140, 22);
            ownersPartiesMenuItem.Text = "&Owners";
            ownersPartiesMenuItem.Click += ownersPartiesMenuItem_Click;
            // 
            // adminToolStripMenuItem
            // 
            adminToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { usersToolStripMenuItem, sessionsToolStripMenuItem, sessionEventsToolStripMenuItem, rolesAndPermissionsToolStripMenuItem });
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
            logsToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { allEventsToolStripMenuItem, loginAttemptsToolStripMenuItem, userChangesToolStripMenuItem, locationChangesToolStripMenuItem, skuChangesToolStripMenuItem });
            logsToolStripMenuItem.Name = "logsToolStripMenuItem";
            logsToolStripMenuItem.Size = new Size(116, 22);
            logsToolStripMenuItem.Text = "&Logs";
            // 
            // allEventsToolStripMenuItem
            // 
            allEventsToolStripMenuItem.Name = "allEventsToolStripMenuItem";
            allEventsToolStripMenuItem.Size = new Size(156, 22);
            allEventsToolStripMenuItem.Text = "&All events";
            allEventsToolStripMenuItem.Click += allEventsToolStripMenuItem_Click;
            // 
            // loginAttemptsToolStripMenuItem
            // 
            loginAttemptsToolStripMenuItem.Name = "loginAttemptsToolStripMenuItem";
            loginAttemptsToolStripMenuItem.Size = new Size(156, 22);
            loginAttemptsToolStripMenuItem.Text = "Login &Attempts";
            loginAttemptsToolStripMenuItem.Click += loginAttemptsToolStripMenuItem_Click;
            // 
            // userChangesToolStripMenuItem
            // 
            userChangesToolStripMenuItem.Name = "userChangesToolStripMenuItem";
            userChangesToolStripMenuItem.Size = new Size(156, 22);
            userChangesToolStripMenuItem.Text = "&User changes";
            userChangesToolStripMenuItem.Click += userChangesToolStripMenuItem_Click;
            // 
            // locationChangesToolStripMenuItem
            // 
            locationChangesToolStripMenuItem.Name = "locationChangesToolStripMenuItem";
            locationChangesToolStripMenuItem.Size = new Size(156, 22);
            locationChangesToolStripMenuItem.Text = "&Location changes";
            locationChangesToolStripMenuItem.Click += locationChangesToolStripMenuItem_Click;
            // 
            // skuChangesToolStripMenuItem
            // 
            skuChangesToolStripMenuItem.Name = "skuChangesToolStripMenuItem";
            skuChangesToolStripMenuItem.Size = new Size(156, 22);
            skuChangesToolStripMenuItem.Text = "&SKU changes";
            skuChangesToolStripMenuItem.Click += skuChangesToolStripMenuItem_Click;
            // 
            // warehouseToolStripMenuItem
            // 
            warehouseToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { warehouseTasksToolStripMenuItem, locationsToolStripMenuItem, zonesToolStripMenuItem, sectionsToolStripMenuItem });
            warehouseToolStripMenuItem.Name = "warehouseToolStripMenuItem";
            warehouseToolStripMenuItem.Size = new Size(80, 20);
            warehouseToolStripMenuItem.Text = "&Warehouse";
            // 
            // warehouseTasksToolStripMenuItem
            // 
            warehouseTasksToolStripMenuItem.Name = "warehouseTasksToolStripMenuItem";
            warehouseTasksToolStripMenuItem.Size = new Size(140, 22);
            warehouseTasksToolStripMenuItem.Text = "&Tasks";
            warehouseTasksToolStripMenuItem.Click += warehouseTasksToolStripMenuItem_Click;
            // 
            // locationsToolStripMenuItem (moved to Warehouse)
            // 
            locationsToolStripMenuItem.Name = "locationsToolStripMenuItem";
            locationsToolStripMenuItem.Size = new Size(140, 22);
            locationsToolStripMenuItem.Text = "&Locations";
            locationsToolStripMenuItem.Click += locationsToolStripMenuItem_Click;
            // 
            // zonesToolStripMenuItem
            // 
            zonesToolStripMenuItem.Name = "zonesToolStripMenuItem";
            zonesToolStripMenuItem.Size = new Size(140, 22);
            zonesToolStripMenuItem.Text = "&Zones";
            zonesToolStripMenuItem.Click += zonesToolStripMenuItem_Click;
            // 
            // sectionsToolStripMenuItem
            // 
            sectionsToolStripMenuItem.Name = "sectionsToolStripMenuItem";
            sectionsToolStripMenuItem.Size = new Size(140, 22);
            sectionsToolStripMenuItem.Text = "&Sections";
            sectionsToolStripMenuItem.Click += sectionsToolStripMenuItem_Click;
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
            aboutPeasyWareToolStripMenuItem.Click += aboutPeasyWareToolStripMenuItem_Click;
            // 
            // versionInfoToolStripMenuItem
            //
            versionInfoToolStripMenuItem.Name = "versionInfoToolStripMenuItem";
            versionInfoToolStripMenuItem.Size = new Size(167, 22);
            versionInfoToolStripMenuItem.Text = "&Version info";
            versionInfoToolStripMenuItem.Click += versionInfoToolStripMenuItem_Click;
            // 
            // databaseVersionToolStripMenuItem
            //
            databaseVersionToolStripMenuItem.Name = "databaseVersionToolStripMenuItem";
            databaseVersionToolStripMenuItem.Size = new Size(167, 22);
            databaseVersionToolStripMenuItem.Text = "&Database version";
            databaseVersionToolStripMenuItem.Click += databaseVersionToolStripMenuItem_Click;
            // 
            // supportToolStripMenuItem
            // 
            supportToolStripMenuItem.Name = "supportToolStripMenuItem";
            supportToolStripMenuItem.Size = new Size(167, 22);
            supportToolStripMenuItem.Text = "Su&pport";
            supportToolStripMenuItem.Click += supportToolStripMenuItem_Click;
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
        private ToolStripMenuItem zonesToolStripMenuItem;
        private ToolStripMenuItem sectionsToolStripMenuItem;
        private ToolStripMenuItem materialsToolStripMenuItem;
        private ToolStripMenuItem partiesToolStripMenuItem;
        private ToolStripMenuItem allPartiesToolStripMenuItem;
        private ToolStripMenuItem suppliersPartiesMenuItem;
        private ToolStripMenuItem customersPartiesMenuItem;
        private ToolStripMenuItem hauliersPartiesMenuItem;
        private ToolStripMenuItem ownersPartiesMenuItem;
        private ToolStripMenuItem suppliersToolStripMenuItem;
        private ToolStripMenuItem customersToolStripMenuItem;
        private ToolStripMenuItem sToolStripMenuItem;
        private ToolStripMenuItem sessionEventsToolStripMenuItem;
        private ToolStrip mainToolStrip;
        private ToolStripMenuItem logsToolStripMenuItem;
        private ToolStripMenuItem allEventsToolStripMenuItem;
        private ToolStripMenuItem loginAttemptsToolStripMenuItem;
        private ToolStripMenuItem userChangesToolStripMenuItem;
        private ToolStripMenuItem locationChangesToolStripMenuItem;
        private ToolStripMenuItem skuChangesToolStripMenuItem;
        private ToolStripMenuItem operationalSettingsToolStripMenuItem;
        private ToolStripMenuItem clientSettingsToolStripMenuItem;
        private StatusStrip statusStrip1;
        private ToolStripStatusLabel toolStripStatusLabel1;
        private ToolStripMenuItem inventoryActiveToolStripMenuItem;
        private ToolStripMenuItem outstandiToolStripMenuItem;
        private ToolStripMenuItem departedToolStripMenuItem;
        private ToolStripMenuItem allToolStripMenuItem;
        private ToolStripMenuItem shipmentsToolStripMenuItem;
        private ToolStripMenuItem outstandingToolStripMenuItem;
        private ToolStripMenuItem departedToolStripMenuItem1;
        private ToolStripMenuItem allToolStripMenuItem1;
        private ToolStripMenuItem warehouseToolStripMenuItem;
        private ToolStripMenuItem warehouseTasksToolStripMenuItem;
    }
}