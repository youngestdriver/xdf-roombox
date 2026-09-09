# 抓取 Qt 对话框并用像素分析定位按钮
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class DlgPix {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static IntPtr Find(uint targetPid, string title) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == targetPid && IsWindowVisible(h)) {
        var t = new StringBuilder(256); GetWindowText(h, t, 256);
        if (t.ToString() == title) { found = h; return false; }
      }
      return true;
    }, IntPtr.Zero);
    return found;
  }
}
"@
$procId = (Get-Process Roombox | Select-Object -First 1).Id
$h = [DlgPix]::Find([uint32]$procId, "Dialog")
if ($h -eq [IntPtr]::Zero) { Write-Output "无对话框"; exit 1 }
$r = New-Object DlgPix+RECT
[DlgPix]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $ht = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[DlgPix]::PrintWindow($h, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save("$PSScriptRoot\dialog_pw.png", [System.Drawing.Imaging.ImageFormat]::Png)

# 像素分析: 找青绿色按钮 (#00C896 附近, R<100, G>150, B>100)
$regions = @{}
for ($y = 0; $y -lt $ht; $y += 2) {
  for ($x = 0; $x -lt $w; $x += 2) {
    $c = $bmp.GetPixel($x, $y)
    if ($c.R -lt 100 -and $c.G -gt 140 -and $c.B -gt 90 -and $c.B -lt 220) {
      $key = [int]($x / 40)  # 按40px分列
      if (-not $regions.ContainsKey($key)) { $regions[$key] = @{ minX = $x; maxX = $x; minY = $y; maxY = $y; count = 0 } }
      $reg = $regions[$key]
      if ($x -lt $reg.minX) { $reg.minX = $x }
      if ($x -gt $reg.maxX) { $reg.maxX = $x }
      if ($y -lt $reg.minY) { $reg.minY = $y }
      if ($y -gt $reg.maxY) { $reg.maxY = $y }
      $reg.count++
    }
  }
}
$bmp.Dispose()
Write-Output "窗口位置: ($($r.L),$($r.T)) 尺寸: ${w}x${ht}"
Write-Output "=== 绿色像素区域 (按列分组) ==="
foreach ($k in ($regions.Keys | Sort-Object)) {
  $reg = $regions[$k]
  if ($reg.count -gt 20) {
    $cx = [int](($reg.minX + $reg.maxX) / 2)
    $cy = [int](($reg.minY + $reg.maxY) / 2)
    Write-Output ("  区域: x=$($reg.minX)-$($reg.maxX) y=$($reg.minY)-$($reg.maxY) 像素数=$($reg.count) -> 中心($cx,$cy) 屏幕($($r.L+$cx),$($r.T+$cy))")
  }
}
