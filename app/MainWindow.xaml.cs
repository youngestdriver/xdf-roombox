using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using XdfRoombox.Models;
using XdfRoombox.Services;

namespace XdfRoombox;

public partial class MainWindow : Window
{
    private readonly AppConfig _cfg;
    private readonly ClassWatcher _watcher;
    private readonly DispatcherTimer _timer;
    private readonly ObservableCollection<LogEntry> _logs = new();
    private bool _running = true;
    private bool _busy;
    private static readonly string ConfigPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "XdfRoombox", "config.json");
    private static readonly string LogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "XdfRoombox", "app.log");

    public MainWindow()
    {
        InitializeComponent();
        _cfg = LoadConfig();

        var cdp = new CdpClient(_cfg.DebugPort);
        var roombox = new RoomboxManager(_cfg);
        _watcher = new ClassWatcher(_cfg, cdp, roombox, Log);

        LogList.ItemsSource = _logs;

        // 初始化 UI
        ChkEnter.IsChecked = _cfg.AutoEnter;
        ChkSignIn.IsChecked = _cfg.AutoSignIn;
        ChkExit.IsChecked = _cfg.AutoExit;
        ChkEval.IsChecked = _cfg.AutoEvaluate;
        TxtAhead.Text = (_cfg.EnterAheadSeconds / 60).ToString();
        TxtExitDelay.Text = (_cfg.ExitDelaySeconds / 60).ToString();
        TxtEvalOpt.Text = _cfg.EvaluateOption.ToString();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(_cfg.PollSeconds) };
        _timer.Tick += async (_, _) => await TickAsync();
        _timer.Start();

        Log("INFO", "助手已启动，正在监控...");
        _ = TickAsync(); // 立即跑一轮
    }

    private async Task TickAsync()
    {
        if (_busy || !_running) return;
        _busy = true;
        try
        {
            await _watcher.TickAsync();
            UpdateUi();
        }
        catch (Exception ex) { Log("ERROR", "检查出错: " + ex.Message); }
        finally { _busy = false; }
    }

    private void UpdateUi()
    {
        var s = _watcher.State;
        DotProcess.Fill = (System.Windows.Media.Brush)FindResource(s.RoomboxRunning ? "OkBrush" : "ErrBrush");
        DotDebug.Fill = (System.Windows.Media.Brush)FindResource(s.DebugPortReady ? "OkBrush" : "ErrBrush");
        DotClass.Fill = (System.Windows.Media.Brush)FindResource(s.InClassroom ? "OkBrush" : "ErrBrush");

        TxtCurrent.Text = s.CurrentLesson?.ClassroomName ?? "—";
        TxtCurrentTime.Text = s.CurrentLesson != null
            ? $"{s.CurrentLesson.StartLocal:HH:mm} - {s.CurrentLesson.EndLocal:HH:mm}  主讲: {s.CurrentLesson.TeacherName}"
            : "";
        TxtNext.Text = s.NextLesson?.ClassroomName ?? "—";
        TxtNextTime.Text = s.NextLesson != null
            ? $"{s.NextLesson.StartLocal:MM-dd HH:mm} 开始  主讲: {s.NextLesson.TeacherName}"
            : "";
        TxtStatus.Text = s.LastAction;

        if (s.LastTick != DateTime.MinValue)
            TxtToken.Text = $"上次检查 {s.LastTick:HH:mm:ss}";
        if (s.TokenExp > 0)
        {
            var left = DateTimeOffset.FromUnixTimeSeconds(s.TokenExp) - DateTimeOffset.UtcNow;
            TxtToken.Text += (TxtToken.Text.Length > 0 ? " · " : "") + $"token 剩余 {left.Days} 天";
        }
    }

    private void Log(string level, string msg)
    {
        Dispatcher.Invoke(() =>
        {
            var entry = new LogEntry { Level = level, Message = msg };
            _logs.Add(entry);
            while (_logs.Count > 300) _logs.RemoveAt(0);
            if (_logs.Count > 0) LogList.ScrollIntoView(_logs[^1]);
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
                File.AppendAllText(LogPath, entry + Environment.NewLine);
            }
            catch { }
        });
    }

    // ---------------- 事件 ----------------

    private void OnToggle(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded) return;
        _cfg.AutoEnter = ChkEnter.IsChecked == true;
        _cfg.AutoSignIn = ChkSignIn.IsChecked == true;
        _cfg.AutoExit = ChkExit.IsChecked == true;
        _cfg.AutoEvaluate = ChkEval.IsChecked == true;
        SaveConfig();
    }

    private void OnToggleMonitor(object sender, RoutedEventArgs e)
    {
        _running = !_running;
        BtnToggle.Content = _running ? "暂停监控" : "开始监控";
        Log("INFO", _running ? "监控已恢复" : "监控已暂停");
        if (_running) _ = TickAsync();
    }

    private async void OnCheckNow(object sender, RoutedEventArgs e)
    {
        Log("INFO", "手动触发检查...");
        await TickAsync();
    }

    private void OnOpenSettings(object sender, RoutedEventArgs e)
    {
        var win = new SettingsWindow(_cfg) { Owner = this };
        if (win.ShowDialog() == true)
        {
            SaveConfig();
            _timer.Interval = TimeSpan.FromSeconds(_cfg.PollSeconds);
            Log("INFO", "设置已保存");
        }
    }

    // ---------------- 配置 ----------------

    private static AppConfig LoadConfig()
    {
        try
        {
            if (File.Exists(ConfigPath))
                return JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(ConfigPath)) ?? new AppConfig();
        }
        catch { }
        return new AppConfig();
    }

    private void SaveConfig()
    {
        try
        {
            // 从界面回读参数
            if (int.TryParse(TxtAhead.Text, out var m) && m > 0) _cfg.EnterAheadSeconds = m * 60;
            if (int.TryParse(TxtExitDelay.Text, out var x) && x >= 0) _cfg.ExitDelaySeconds = x * 60;
            if (int.TryParse(TxtEvalOpt.Text, out var o) && o >= 1 && o <= 3) _cfg.EvaluateOption = o;

            Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(_cfg, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex) { Log("ERROR", "保存配置失败: " + ex.Message); }
    }

    protected override void OnClosed(EventArgs e)
    {
        SaveConfig();
        base.OnClosed(e);
    }
}
