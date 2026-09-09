using System.Diagnostics;
using System.IO;
using XdfRoombox.Models;

namespace XdfRoombox.Services;

/// <summary>云教室进程管理：检测/启动（带调试参数）</summary>
public class RoomboxManager
{
    private readonly AppConfig _cfg;
    public RoomboxManager(AppConfig cfg) => _cfg = cfg;

    public bool IsRunning => Process.GetProcessesByName("Roombox").Length > 0;

    /// <summary>启动云教室（带 CDP 调试端口与防节流参数）</summary>
    public bool Start()
    {
        if (!File.Exists(_cfg.RoomboxExe)) return false;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = _cfg.RoomboxExe,
                Arguments = $"--remote-debugging-port={_cfg.DebugPort} " +
                            "--disable-background-timer-throttling --disable-renderer-backgrounding " +
                            "--disable-backgrounding-occluded-windows --disable-features=IntensiveWakeUpThrottling",
                WorkingDirectory = Path.GetDirectoryName(_cfg.RoomboxExe) ?? ""
            });
            return true;
        }
        catch { return false; }
    }

    /// <summary>等待调试端口就绪（最多 timeoutSec 秒）</summary>
    public async Task<bool> WaitForDebugPortAsync(int timeoutSec = 120)
    {
        var cdp = new CdpClient(_cfg.DebugPort);
        for (var i = 0; i < timeoutSec / 2; i++)
        {
            if (await cdp.GetTargetsAsync() != null) return true;
            await Task.Delay(2000);
        }
        return false;
    }
}
