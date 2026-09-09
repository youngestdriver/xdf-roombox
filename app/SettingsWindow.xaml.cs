using System.Windows;
using Microsoft.Win32;
using XdfRoombox.Models;

namespace XdfRoombox;

public partial class SettingsWindow : Window
{
    private readonly AppConfig _cfg;

    public SettingsWindow(AppConfig cfg)
    {
        InitializeComponent();
        _cfg = cfg;
        TxtExe.Text = cfg.RoomboxExe;
        TxtPort.Text = cfg.DebugPort.ToString();
        TxtPoll.Text = cfg.PollSeconds.ToString();
        ChkMinimized.IsChecked = cfg.StartMinimized;
        TxtComment.Text = cfg.EvaluateComment;
    }

    private void OnBrowse(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Filter = "Roombox.exe|Roombox.exe|可执行文件|*.exe" };
        if (dlg.ShowDialog() == true) TxtExe.Text = dlg.FileName;
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(TxtPort.Text, out var port) || port < 1 || port > 65535)
        {
            MessageBox.Show("端口无效", "设置", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!int.TryParse(TxtPoll.Text, out var poll) || poll < 5)
        {
            MessageBox.Show("轮询间隔至少 5 秒", "设置", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _cfg.RoomboxExe = TxtExe.Text.Trim();
        _cfg.DebugPort = port;
        _cfg.PollSeconds = poll;
        _cfg.StartMinimized = ChkMinimized.IsChecked == true;
        _cfg.EvaluateComment = TxtComment.Text.Trim();
        DialogResult = true;
        Close();
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
