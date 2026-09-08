# 新东方云教室 API 清单提取脚本
# 用法: powershell -File extract_endpoints.ps1
# 流程: 拉取课表 webapp 的 index.html -> 发现并下载全部 JS bundle -> 正则提取 API 路径/域名
#       -> 合并本地应用日志中的完整 URL -> 生成 endpoints.md / endpoints_raw.json
param(
  [string]$OutDir  = "C:\Users\PaperCrane\Desktop\code\xdf_roombox",
  [string]$IndexUrl = "https://d.roombox.xdf.cn/schedule/"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir, "$OutDir\js", "$OutDir\raw" | Out-Null

# 1) index.html -> 发现全部 chunk js
$html = (Invoke-WebRequest -Uri $IndexUrl -TimeoutSec 30).Content
$html | Out-File "$OutDir\raw\index.html" -Encoding utf8
$chunks = @([regex]::Matches($html, 'static/js/[^"''\s]+\.js') | ForEach-Object { $_.Value } | Sort-Object -Unique)
Write-Output ("发现 chunk: " + ($chunks -join ', '))
foreach ($c in $chunks) {
  try { Invoke-WebRequest -Uri ($IndexUrl.TrimEnd('/') + '/' + $c) -OutFile "$OutDir\js\$($c.Replace('static/js/',''))" -TimeoutSec 60 }
  catch { Write-Output ("skip: " + $c) }
}

# 2) 从 JS 提取 API 路径 / 域名 / 完整 URL
$jsApi = [System.Collections.Generic.HashSet[string]]::new()
$jsHosts = [System.Collections.Generic.HashSet[string]]::new()
$jsFullUrls = [System.Collections.Generic.HashSet[string]]::new()
foreach ($f in Get-ChildItem "$OutDir\js\*.js") {
  $txt = Get-Content $f.FullName -Raw
  foreach ($m in [regex]::Matches($txt, '(/api/[A-Za-z0-9_\-./?=&%${}:{},]{1,160})')) {
    [void]$jsApi.Add(($m.Groups[1].Value -replace '\$\{[^}]*\}', '{}'))
  }
  foreach ($m in [regex]::Matches($txt, '(https?://[a-z0-9.\-]+\.(?:roombox|coursebox)\.xdf\.cn[A-Za-z0-9_\-./?=&%${}:{},]{0,120})')) {
    [void]$jsFullUrls.Add(($m.Groups[1].Value -replace '\$\{[^}]*\}', '{}'))
  }
  foreach ($m in [regex]::Matches($txt, '([a-z0-9\-]+\.(?:roombox|coursebox)\.xdf\.cn)')) {
    [void]$jsHosts.Add($m.Groups[1].Value)
  }
  foreach ($m in [regex]::Matches($txt, '(/polaris/[A-Za-z0-9_\-./?=&%${}:{},]{1,120})')) {
    [void]$jsApi.Add(($m.Groups[1].Value -replace '\$\{[^}]*\}', '{}'))
  }
}

# 3) 合并本地日志 URL（token 打码）
$logFile = Get-ChildItem "$env:APPDATA\RoomboxData\logs" -Recurse -Filter "Roombox_2*.log" |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$logUrls = @()
if ($logFile) {
  $logUrls = [regex]::Matches((Get-Content $logFile.FullName -Raw), 'https?://[^\s"''<>)]+') |
    ForEach-Object { $_.Value -replace 'fetchToken/[A-Za-z0-9_\-\.]+', 'fetchToken/<JWT>' } |
    Sort-Object -Unique
}

# 4) 输出
$json = [ordered]@{
  generated_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  sources = @("$IndexUrl 前端 bundle", "日志 $($logFile.Name)")
  auth = 'JWT(HS512, sub=userId), URL query 参数 token=, 约14天有效'
  js_api_paths  = @($jsApi | Sort-Object)
  domains       = @($jsHosts | Sort-Object)
  js_full_urls  = @($jsFullUrls | Sort-Object)
  log_urls      = $logUrls
}
$json | ConvertTo-Json -Depth 6 | Out-File "$OutDir\endpoints_raw.json" -Encoding utf8

$md = @"
# 新东方云教室 API 清单（自动提取）

- 生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- 来源: $IndexUrl 前端 bundle、本地日志 $($logFile.Name)
- 认证: JWT(HS512, sub=用户ID), URL ``token=`` 参数, 约14天有效；获取方式见 README.md

## 域名
$(($jsHosts | Sort-Object) -join "`n")

## REST 相对路径(前缀 https://api.roombox.xdf.cn)
$(($jsApi | Sort-Object) -join "`n")

## bundle 完整 URL
$(($jsFullUrls | Sort-Object) -join "`n")

## 日志 URL
$($logUrls -join "`n")
"@
$md | Out-File "$OutDir\endpoints.md" -Encoding utf8
Write-Output ("完成: " + $jsApi.Count + " 路径, " + $jsHosts.Count + " 域名, " + $logUrls.Count + " 日志URL")
