using System.Windows.Forms;

namespace PeasyWare.Desktop.Infrastructure.Ui;

/// <summary>
/// Small helper for RBAC-based UI gating (Phase 2d).
///
/// Convention: disable, don't hide. WMS/ERP users benefit from seeing
/// the full menu/toolbar structure even when a specific action is off
/// limits to their role, rather than wondering why something vanished.
///
/// This is UX only - the database guard (auth.fn_has_permission,
/// Phase 2c) is the actual security boundary. Gating here just keeps
/// the UI honest about what will happen if the control is used; it is
/// not a substitute for the SP-level check.
/// </summary>
public static class PermissionGating
{
    public const string DeniedTooltip = "You don't have permission for this action.";

    /// <summary>
    /// Disables a toolbar item (and sets an explanatory tooltip) when the
    /// permission is not held. Returns the granted state so callers can
    /// combine it with other enablement conditions, e.g.:
    /// <c>_btnEnable.Enabled = _canManageUsers.GateBy(_btnEnable) &amp;&amp; !user.IsActive;</c>
    /// </summary>
    public static bool GateBy(this ToolStripItem item, bool granted)
    {
        item.Enabled = granted;
        item.ToolTipText = granted ? null : DeniedTooltip;
        return granted;
    }

    /// <summary>
    /// Disables a plain Control (button, etc.) when the permission is not
    /// held. Pass the form's ToolTip component to also surface why.
    /// </summary>
    public static bool GateBy(this Control control, bool granted, ToolTip? toolTip = null, string? deniedText = null)
    {
        control.Enabled = granted;
        toolTip?.SetToolTip(control, granted ? "" : (deniedText ?? DeniedTooltip));
        return granted;
    }
}
