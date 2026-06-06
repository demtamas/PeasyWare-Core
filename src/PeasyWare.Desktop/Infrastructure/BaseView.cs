using PeasyWare.Desktop.Forms;
using System;
using System.Windows.Forms;

namespace PeasyWare.Desktop.Infrastructure;

public partial class BaseView : UserControl
{
    private MainForm? _main;

    protected MainForm? Main
    {
        get
        {
            if (DesignMode)
                return null;

            _main ??= FindForm() as MainForm;
            return _main;
        }
    }

    protected void Execute(Action action)
    {
        if (Main is null)
            return;

        Main.ExecuteWithSession(action);
    }

    /// <summary>
    /// Runs <paramref name="dbWork"/> on a thread-pool thread, then calls
    /// <paramref name="uiCallback"/> on the UI thread with the result.
    /// The wait cursor is shown for the duration.
    /// </summary>
    protected void ExecuteAsync<T>(
        Func<T>    dbWork,
        Action<T>  uiCallback)
    {
        if (Main is null) return;
        if (Main.GetIsSessionExpired()) return;

        Main.Cursor = System.Windows.Forms.Cursors.WaitCursor;

        System.Threading.Tasks.Task.Run(dbWork)
            .ContinueWith(t =>
            {
                Main.Cursor = System.Windows.Forms.Cursors.Default;

                if (t.IsFaulted)
                {
                    System.Windows.Forms.MessageBox.Show(
                        t.Exception?.InnerException?.Message ?? "Unexpected error.",
                        "Error",
                        System.Windows.Forms.MessageBoxButtons.OK,
                        System.Windows.Forms.MessageBoxIcon.Error);
                    return;
                }

                uiCallback(t.Result);

            }, System.Threading.Tasks.TaskScheduler.FromCurrentSynchronizationContext());
    }

    protected EventHandler Wrap(Action action)
    {
        return (_, _) => Execute(action);
    }

    protected bool CanExecute()
    {
        return Main is not null && !Main.GetIsSessionExpired();
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

