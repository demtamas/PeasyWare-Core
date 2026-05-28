using System.Drawing;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Locations;

public sealed class LockReasonForm : Form
{
    private readonly TextBox _txtReason = new() { Multiline = false, Width = 340 };
    public string? Reason => string.IsNullOrWhiteSpace(_txtReason.Text) ? null : _txtReason.Text.Trim();

    public LockReasonForm(string binCode)
    {
        Text            = $"Lock — {binCode}";
        Size            = new Size(420, 160);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterParent;

        var lbl = new Label { Text = "Reason (optional):", Location = new Point(16, 20), AutoSize = true };
        _txtReason.Location    = new Point(16, 44);
        _txtReason.PlaceholderText = "e.g. Maintenance, damaged racking...";

        var btnOk     = new Button { Text = "Lock",   Width = 80, Height = 28, Location = new Point(16, 82),  DialogResult = DialogResult.OK };
        var btnCancel = new Button { Text = "Cancel", Width = 80, Height = 28, Location = new Point(104, 82), DialogResult = DialogResult.Cancel };

        Controls.AddRange([lbl, _txtReason, btnOk, btnCancel]);
        AcceptButton = btnOk;
        CancelButton = btnCancel;
    }
}
