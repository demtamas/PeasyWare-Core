using System;
using System.Runtime.InteropServices;

namespace PeasyWare.Desktop.Infrastructure;

/// <summary>
/// Writes text to the Windows clipboard using Win32 API directly,
/// bypassing the OLE layer that requires STA thread mode.
/// Safe to call from any thread.
/// </summary>
internal static class ClipboardHelper
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    private const uint CF_UNICODETEXT = 13;
    private const uint GMEM_MOVEABLE  = 0x0002;

    /// <summary>
    /// Sets the clipboard text using Win32 API directly.
    /// Returns true if successful.
    /// </summary>
    public static bool SetText(string text)
    {
        if (string.IsNullOrEmpty(text)) return false;

        try
        {
            if (!OpenClipboard(IntPtr.Zero)) return false;

            EmptyClipboard();

            // Allocate global memory for the text (Unicode, null-terminated)
            var bytes = (text.Length + 1) * 2;
            var hMem  = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes);
            if (hMem == IntPtr.Zero) { CloseClipboard(); return false; }

            var ptr = GlobalLock(hMem);
            if (ptr == IntPtr.Zero) { CloseClipboard(); return false; }

            Marshal.Copy(text.ToCharArray(), 0, ptr, text.Length);
            Marshal.WriteInt16(ptr + text.Length * 2, 0); // null terminator

            GlobalUnlock(hMem);
            SetClipboardData(CF_UNICODETEXT, hMem);

            return true;
        }
        finally
        {
            CloseClipboard();
        }
    }
}
