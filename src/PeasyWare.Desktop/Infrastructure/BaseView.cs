using PeasyWare.Application.Security;
using PeasyWare.Desktop.Forms;
using PeasyWare.Desktop.Infrastructure.Ui;
using System;
using System.Windows.Forms;
using static System.Windows.Forms.VisualStyles.VisualStyleElement;

namespace PeasyWare.Desktop.Infrastructure;

public abstract partial class BaseView : UserControl
{
    private MainForm? _main;

    protected MainForm Main
    {
        get
        {
            _main ??= FindForm() as MainForm;
            return _main!;
        }
    }

    protected void Execute(Action action)
    {
        if (Main == null)
            return;

        Main.ExecuteWithSession(action);
    }

    protected EventHandler Wrap(Action action)
    {
        return (_, _) => Execute(action);
    }

    protected bool CanExecute()
    {
        return Main != null && !Main.GetIsSessionExpired();
    }
}

/*

Add this helper in BaseView:

protected ToolStripButton CreateButton(
    string text,
    Image icon,
    Action action,
    bool enabled = true)
    {
        return new ToolStripButton(text)
        {
            Image = icon,
            Enabled = enabled,
            DisplayStyle = ToolStripItemDisplayStyle.ImageAndText
        }.Also(btn => btn.Click += Wrap(action));
    }

    Then your toolbar becomes:

_btnRefresh = CreateButton("Refresh", Icons.Refresh, LoadSettings);
_btnEdit = CreateButton("Edit highlighted", Icons.Edit, EditSelectedSetting, false);

*/

