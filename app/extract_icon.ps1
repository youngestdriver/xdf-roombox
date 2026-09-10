# 从 Roombox.exe 提取图标, 打包为多尺寸 .ico
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class IconExtract {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int PrivateExtractIcons(string file, int idx, int cx, int cy, IntPtr[] phicon, int[] piconid, int nIcons, int flags);
  [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
}
"@

$src = "D:\soft\XDF\Roombox\2.74.3.2063\Roombox.exe"
$outIco = "C:\Users\PaperCrane\Desktop\code\xdf_roombox\app\app.ico"
$sizes = @(256, 128, 64, 48, 32, 16)
$pngs = @()

foreach ($size in $sizes) {
  $ph = New-Object IntPtr[] 1
  $got = [IconExtract]::PrivateExtractIcons($src, 0, $size, $size, $ph, $null, 1, 0)
  if ($got -gt 0 -and $ph[0] -ne [IntPtr]::Zero) {
    $icon = [System.Drawing.Icon]::FromHandle($ph[0])
    $bmp = $icon.ToBitmap()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += ,@{ Size = $size; Data = $ms.ToArray() }
    if ($size -eq 256) { $bmp.Save("C:\Users\PaperCrane\Desktop\code\xdf_roombox\app\icon_preview.png", [System.Drawing.Imaging.ImageFormat]::Png) }
    $bmp.Dispose()
    [IconExtract]::DestroyIcon($ph[0]) | Out-Null
    $ms.Dispose()
    Write-Output "提取 ${size}x${size} OK"
  } else {
    Write-Output "提取 ${size}x${size} 失败"
  }
}

# 组装 ICO 容器 (PNG 压缩格式, Vista+ 支持)
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
  $sz = $p.Size
  $w = if ($sz -ge 256) { 0 } else { $sz }
  $bw.Write([byte]$w); $bw.Write([byte]$w)
  $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([UInt16]1); $bw.Write([UInt16]32)
  $bw.Write([UInt32]$p.Data.Length)
  $bw.Write([UInt32]$offset)
  $offset += $p.Data.Length
}
foreach ($p in $pngs) { $bw.Write($p.Data) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($outIco, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

Write-Output ("`n已生成: " + $outIco + "  (" + [math]::Round((Get-Item $outIco).Length/1KB, 1) + " KB, " + $pngs.Count + " 种尺寸)")
