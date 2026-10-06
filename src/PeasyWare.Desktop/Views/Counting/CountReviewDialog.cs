using PeasyWare.Application.Dto;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Views.Counting;

/// <summary>
/// Asks the reviewer to say what was done about a count's findings before it
/// is marked reviewed. Lists the findings that need review so the note is
/// written with them in front of you; "Mark reviewed" stays disabled until
/// there is a note (the procedure refuses an empty one as well).
/// </summary>
public sealed class CountReviewDialog : Form
{
    private readonly TextBox _txtNote = new()
    {
        Multiline  = true,
        MaxLength  = 500,
        ScrollBars = ScrollBars.Vertical,
        Dock       = DockStyle.Fill
    };

    private readonly Button _btnOk     = new() { Text = "Mark reviewed", DialogResult = DialogResult.OK, Enabled = false, AutoSize = true };
    private readonly Button _btnCancel = new() { Text = "Cancel",        DialogResult = DialogResult.Cancel, AutoSize = true };

    /// <summary>What was done about the findings, as typed by the reviewer.</summary>
    public string Note => _txtNote.Text.Trim();

    public CountReviewDialog(CountSessionDto session, IReadOnlyList<CountFindingDto> findings)
    {
        Text            = $"Review count #{session.CountId}";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition   = FormStartPosition.CenterParent;
        MaximizeBox     = false;
        MinimizeBox     = false;
        Size            = new Size(640, 440);

        var toReview = findings.Where(f => f.NeedsReview).ToList();

        var layout = new TableLayoutPanel
        {
            Dock        = DockStyle.Fill,
            Padding     = new Padding(12),
            ColumnCount = 1,
            RowCount    = 4
        };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 24F));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent,  50F));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 24F));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent,  50F));

        layout.Controls.Add(new Label
        {
            Text      = $"{toReview.Count} finding(s) on this count need review:",
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft,
            Font      = new Font(Font, FontStyle.Bold)
        }, 0, 0);

        var list = new ListBox
        {
            Dock                = DockStyle.Fill,
            SelectionMode       = SelectionMode.None,
            HorizontalScrollbar = true,
            IntegralHeight      = false
        };
        list.Items.AddRange(toReview.Select(Describe).Cast<object>().ToArray());
        layout.Controls.Add(list, 0, 1);

        layout.Controls.Add(new Label
        {
            Text      = "What was done about them? (required)",
            Dock      = DockStyle.Fill,
            TextAlign = ContentAlignment.BottomLeft
        }, 0, 2);

        layout.Controls.Add(_txtNote, 0, 3);

        var buttons = new FlowLayoutPanel
        {
            Dock          = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            Height        = 44,
            Padding       = new Padding(8)
        };
        buttons.Controls.Add(_btnCancel);
        buttons.Controls.Add(_btnOk);

        Controls.Add(layout);
        Controls.Add(buttons);

        // No AcceptButton on purpose: Enter in a note should not submit a review
        CancelButton = _btnCancel;

        _txtNote.TextChanged += (_, _) => _btnOk.Enabled = _txtNote.Text.Trim().Length > 0;
    }

    private static string Describe(CountFindingDto f)
    {
        var what = f.FindingCode switch
        {
            "UNKNOWN_UNIT" => "unknown pallet",
            "NOT_CORRECTED" => f.ReasonMessage ?? "could not be corrected",
            _ => f.FindingCode
        };

        var where = "";

        if (f.ShipmentRef is not null)
        {
            where = $"   [left on {f.ShipmentRef}";

            if (f.OrderRef is not null)
                where += $", order {f.OrderRef}";

            if (!string.IsNullOrWhiteSpace(f.CustomerName))
                where += $" - {f.CustomerName}";

            where += "]";
        }

        return $"{f.BinCode}   {f.ScannedRef}   {f.SkuCode}   {what}{where}";
    }
}
