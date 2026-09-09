using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace XdfRoombox.Services;

/// <summary>
/// 处理云教室的 Qt 原生确认对话框（如「确定要退出吗？」）。
/// 云教室的对话框是 Qt 绘制的分层窗口，CDP 与 UIAutomation 都无法操作，
/// 唯一可靠方式是模拟真实鼠标点击「确定」按钮（相对窗口 70% 宽、67% 高）。
/// </summary>
public static class QtDialogCloser
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X, Y; }

    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;

    /// <summary>查找云教室进程的 Qt "Dialog" 窗口（确认框）</summary>
    public static IntPtr FindDialog()
    {
        var pids = Process.GetProcessesByName("Roombox").Select(p => (uint)p.Id).ToHashSet();
        if (pids.Count == 0) return IntPtr.Zero;
        var found = IntPtr.Zero;
        EnumWindows((h, _) =>
        {
            GetWindowThreadProcessId(h, out var pid);
            if (!pids.Contains(pid) || !IsWindowVisible(h)) return true;
            var sb = new StringBuilder(64);
            GetWindowText(h, sb, 64);
            if (sb.ToString() == "Dialog") { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    /// <summary>点击对话框右侧「确定」按钮（相对位置 70% / 67%，实测校准）</summary>
    public static bool ClickConfirm(IntPtr dialog)
    {
        if (dialog == IntPtr.Zero || !GetWindowRect(dialog, out var r)) return false;
        var w = r.Right - r.Left;
        var h = r.Bottom - r.Top;
        if (w < 50 || h < 50) return false;
        var x = r.Left + (int)(w * 0.70);
        var y = r.Top + (int)(h * 0.67);

        GetCursorPos(out var orig);
        try
        {
            SetCursorPos(x, y);
            Thread.Sleep(150);
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            Thread.Sleep(60);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
            Thread.Sleep(600);
        }
        finally
        {
            SetCursorPos(orig.X, orig.Y); // 恢复鼠标原位
        }
        return true;
    }

    /// <summary>关闭课堂窗口，并在出现「确定要退出吗？」对话框时自动点确定</summary>
    public static async Task<bool> CloseClassroomAsync(CdpClient cdp, string targetId, Action<string, string> log)
    {
        await cdp.CloseTargetAsync(targetId);
        await Task.Delay(2000);

        var dlg = FindDialog();
        if (dlg != IntPtr.Zero)
        {
            log("INFO", "检测到退出确认框，自动点击「确定」");
            await Task.Run(() => ClickConfirm(dlg));
            await Task.Delay(1500);
        }

        var targets = await cdp.GetTargetsAsync();
        return targets?.Any(t => t.Url.Contains("assets.coursebox.xdf.cn/wb")) != true;
    }
}
