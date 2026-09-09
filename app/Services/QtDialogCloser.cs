using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace XdfRoombox.Services;

/// <summary>
/// 处理云教室的 Qt 原生确认对话框（如「确定要退出吗？」）。
/// 该对话框是 Qt 绘制的分层窗口：CDP 与 UIAutomation 均无法操作，
/// 但实测可通过 PostMessage 向窗口投递鼠标消息在**后台**点击「确定」
/// （不需要窗口在前台、不移动真实鼠标）。按钮位置为相对客户区的 70% / 67%。
/// </summary>
public static class QtDialogCloser
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }

    private const uint WM_MOUSEMOVE = 0x0200;
    private const uint WM_LBUTTONDOWN = 0x0201;
    private const uint WM_LBUTTONUP = 0x0202;

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

    /// <summary>
    /// 后台点击对话框右侧「确定」按钮（PostMessage 投递鼠标消息，无需前台）。
    /// 按钮位于客户区 70% 宽 / 67% 高处（实测校准）。
    /// </summary>
    public static bool ClickConfirm(IntPtr dialog)
    {
        if (dialog == IntPtr.Zero || !IsWindow(dialog)) return false;
        if (!GetClientRect(dialog, out var cr)) return false;
        var x = (int)(cr.Right * 0.70);
        var y = (int)(cr.Bottom * 0.67);
        if (x <= 0 || y <= 0) return false;
        var lp = (IntPtr)((y << 16) | (x & 0xFFFF));

        PostMessage(dialog, WM_MOUSEMOVE, IntPtr.Zero, lp);
        Thread.Sleep(100);
        PostMessage(dialog, WM_LBUTTONDOWN, (IntPtr)1, lp);
        Thread.Sleep(80);
        PostMessage(dialog, WM_LBUTTONUP, IntPtr.Zero, lp);
        return true;
    }

    /// <summary>关闭课堂窗口，并在出现「确定要退出吗？」对话框时后台自动点确定</summary>
    public static async Task<bool> CloseClassroomAsync(CdpClient cdp, string targetId, Action<string, string> log)
    {
        await cdp.CloseTargetAsync(targetId);
        await Task.Delay(2000);

        var dlg = FindDialog();
        if (dlg != IntPtr.Zero)
        {
            log("INFO", "检测到退出确认框，后台点击「确定」");
            ClickConfirm(dlg);
            await Task.Delay(1500);

            // 兜底: 若第一次未生效, 重试一次
            var dlg2 = FindDialog();
            if (dlg2 != IntPtr.Zero)
            {
                log("WARN", "确认框仍在，重试点击");
                ClickConfirm(dlg2);
                await Task.Delay(1500);
            }
        }

        var targets = await cdp.GetTargetsAsync();
        return targets?.Any(t => t.Url.Contains("assets.coursebox.xdf.cn/wb")) != true;
    }
}
