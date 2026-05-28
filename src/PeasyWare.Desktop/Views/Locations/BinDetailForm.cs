using PeasyWare.Application.Interfaces;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

/// <summary>Multi-unit bin detail popup — mirrors CLI's detail navigation.</summary>
public sealed class BinDetailForm : Form
{
    public BinDetailForm(string binCode, IInventoryQueryRepository inventoryRepo)
    {
        Text            = $"Bin Detail — {binCode}";
        Size            = new Size(900, 440);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        var dgv = new DataGridView
        {
            Dock                = DockStyle.Fill,
            AutoGenerateColumns = false,
            ReadOnly            = true,
            SelectionMode       = DataGridViewSelectionMode.FullRowSelect,
            AllowUserToAddRows  = false,
            AllowUserToResizeRows = false,
            RowHeadersVisible   = false,
            AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            BackgroundColor     = System.Drawing.SystemColors.Window
        };

        dgv.EnableHeadersVisualStyles = false;
        dgv.ColumnHeadersDefaultCellStyle.BackColor = System.Drawing.SystemColors.Control;
        dgv.ColumnHeadersDefaultCellStyle.Font      = new Font(dgv.Font, FontStyle.Bold);
        dgv.DefaultCellStyle.SelectionBackColor     = System.Drawing.Color.LightSteelBlue;
        dgv.DefaultCellStyle.SelectionForeColor     = System.Drawing.Color.Black;

        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SSCC",        DataPropertyName = "Sscc",              FillWeight = 16 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "SKU",         DataPropertyName = "SkuCode",           FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Description", DataPropertyName = "SkuDescription",    FillWeight = 18 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Qty",         DataPropertyName = "Quantity",          FillWeight = 4  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Batch",       DataPropertyName = "BatchNumber",       FillWeight = 10 });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "BBE",         DataPropertyName = "BestBeforeDate",    FillWeight = 8  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "State",       DataPropertyName = "StockState",        FillWeight = 5  });
        dgv.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Status",      DataPropertyName = "StockStatus",       FillWeight = 5  });

        var units = inventoryRepo.GetActiveInventoryByBin(binCode);
        dgv.DataSource = units.ToList();

        var pnlFooter = new Panel { Dock = DockStyle.Bottom, Height = 44, Padding = new Padding(8, 8, 8, 0) };
        var lblCount  = new Label { Text = $"{units.Count} unit{(units.Count == 1 ? "" : "s")} in {binCode}", AutoSize = true, Location = new System.Drawing.Point(8, 12) };
        var btnClose  = new Button { Text = "Close", Width = 80, Height = 28, DialogResult = DialogResult.OK };
        btnClose.Location = new System.Drawing.Point(pnlFooter.Width - 90, 8);
        btnClose.Anchor   = AnchorStyles.Right | AnchorStyles.Top;
        pnlFooter.Controls.AddRange([lblCount, btnClose]);

        Controls.Add(dgv);
        Controls.Add(pnlFooter);
        AcceptButton = btnClose;
    }
}
