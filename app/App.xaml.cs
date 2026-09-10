using System.Threading;
using System.Windows;

namespace XdfRoombox;

public partial class App : Application
{
    private Mutex? _instanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        // 单实例保护: 防止多开导致重复进教室/重复提交评价
        _instanceMutex = new Mutex(true, @"Global\XdfRoombox_SingleInstance", out var createdNew);
        if (!createdNew)
        {
            MessageBox.Show("新东方云教室助手已在运行中（检查任务栏）。", "提示",
                MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }
        base.OnStartup(e);
    }
}
