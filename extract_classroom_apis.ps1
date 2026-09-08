# 抓取「课上」接口 — 课堂页(白板)Web 应用的前端接口 + 实时 XHR 快照
# 依赖: 云教室已在课堂上并以 --remote-debugging-port=9222 运行
# 用法: pwsh -File extract_classroom_apis.ps1
param(
  [string]$OutDir = "C:\Users\PaperCrane\Desktop\code\xdf_roombox"
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir, "$OutDir\js_wb", "$OutDir\js_wbtools", "$OutDir\js_sdk" | Out-Null

function Log([string]$m) { Write-Output "$(Get-Date -Format 'HH:mm:ss')  $m" }
function Redact([string]$s) { $s -replace '(token|tokdn)=[^&"'']+', '$1=<JWT>' -replace 'startTimestamp=\d+', 'startTimestamp=<ts>' }

# ---- 1) 找课堂页 target ----
$targets = Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json' -TimeoutSec 5
if ($targets -isnot [System.Array]) { $targets = @($targets) }
$wb = $targets | Where-Object { $_.type -eq 'page' -and $_.url -match 'assets\.coursebox\.xdf\.cn/wb' } | Select-Object -First 1
if (-not $wb) { Log '未找到课堂页 target(当前没有处于课堂的窗口?)'; exit 1 }
Log ("课堂页: " + $wb.title + " id=" + $wb.id)

# ---- 2) 实时快照: XHR/fetch + 脚本清单 ----
function Invoke-CdpJs([string]$WsUrl, [string]$Expr) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ct = [System.Threading.CancellationToken]::None
  $payload = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expr; returnByValue = $true } } | ConvertTo-Json -Compress -Depth 8
  try {
    [void]$ws.ConnectAsync([Uri]$WsUrl, $ct).GetAwaiter().GetResult()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
    $buf = [byte[]]::new(8388608); $out = [System.Text.StringBuilder]::new()
    do {
      $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
      [void]$out.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
    } while (-not $r.EndOfMessage)
    $resp = ($out.ToString() | ConvertFrom-Json)
    if ($resp.result.exceptionDetails) { return ('EXC: ' + $resp.result.exceptionDetails.exception.description) }
    return $resp.result.result.value
  } catch { return 'ERR: ' + $_.Exception.Message } finally { $ws.Dispose() }
}
$snapRaw = Invoke-CdpJs $wb.webSocketDebuggerUrl 'JSON.stringify({xhr:performance.getEntriesByType("resource").filter(e=>["xmlhttprequest","fetch"].indexOf(e.initiatorType)>=0).map(e=>e.name), scripts:[...document.querySelectorAll("script[src]")].map(s=>s.src)})'
if ($snapRaw -notmatch '^\{') { Log ('快照失败: ' + $snapRaw); exit 1 }
$snap = $snapRaw | ConvertFrom-Json
if (-not $snap.xhr) { Log '快照失败'; exit 1 }
Log ("实时 XHR 请求数: " + $snap.xhr.Count)

# ---- 3) 下载 bundle(去重) ----
$jsUrls = @($snap.xhr + $snap.scripts | Where-Object { $_ -match '\.js(\?|$)' } | Where-Object { $_ -match 'static/js/|im\.sdk|wbSdk' } | Sort-Object -Unique)
Log ("待下载 bundle: " + $jsUrls.Count)
$downloaded = @()
foreach ($u in $jsUrls) {
  $folder = if ($u -match '/wbtools/') { "$OutDir\js_wbtools" }
            elseif ($u -match 'im\.sdk') { "$OutDir\js_sdk" }
            elseif ($u -match '/wbSdk|wbSdk/') { "$OutDir\js_sdk" }
            else { "$OutDir\js_wb" }
  $name = $u.Split('/')[-1].Split('?')[0]
  $dest = Join-Path $folder $name
  try { Invoke-WebRequest -Uri $u -OutFile $dest -TimeoutSec 60; $downloaded += $u }
  catch { Log ("跳过: " + $u + " (" + $_.Exception.Message + ")") }
}
Log ("已下载: " + $downloaded.Count)

# ---- 4) 从 bundle 提取路径/域名/ws ----
$apiPaths = [System.Collections.Generic.HashSet[string]]::new()
$domains  = [System.Collections.Generic.HashSet[string]]::new()
$wsUrls   = [System.Collections.Generic.HashSet[string]]::new()
$patterns = @('(/api/[A-Za-z0-9_\-./?=&%${}:{},]{1,160})', '(/quiz/[A-Za-z0-9_\-./?=&%${}:{},]{1,160})',
              '(/matrix/[A-Za-z0-9_\-./?=&%${}:{},]{1,160})', '(/polaris/[A-Za-z0-9_\-./?=&%${}:{},]{1,160})',
              '(/classroom/[A-Za-z0-9_\-./?=&%${}:{},]{1,160})', '(wss?://[A-Za-z0-9_\-./:%${}?=&]{4,160})')
foreach ($f in Get-ChildItem "$OutDir\js_wb\*.js", "$OutDir\js_wbtools\*.js", "$OutDir\js_sdk\*.js" -ErrorAction SilentlyContinue) {
  $txt = Get-Content $f.FullName -Raw
  foreach ($pat in $patterns) {
    foreach ($m in [regex]::Matches($txt, $pat)) {
      [void]$apiPaths.Add(($m.Groups[1].Value -replace '\$\{[^}]*\}', '{}'))
    }
  }
  foreach ($m in [regex]::Matches($txt, '([a-z0-9\-]+\.(?:roombox|coursebox|yclassroom|xdfstatic)\.(?:cn|com))')) { [void]$domains.Add($m.Groups[1].Value) }
}
Log ("提取: 路径=" + $apiPaths.Count + " 域名=" + $domains.Count + " ws=" + $wsUrls.Count)

# ---- 5) 落盘 ----
$raw = [ordered]@{
  captured_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  class_context = [ordered]@{ teacherClassId = '623589057'; cid = '623589060'; uid = '25527722'; cType = 4; identity = 3 }
  live_xhr = @($snap.xhr | ForEach-Object { Redact $_ })
  bundle_scripts = $snap.scripts
  ws_url_templates = @($wsUrls | Sort-Object)
  api_paths = @($apiPaths | Sort-Object)
  domains = @($domains | Sort-Object)
  bundles = $downloaded
}
$raw | ConvertTo-Json -Depth 8 | Out-File "$OutDir\endpoints_classroom_raw.json" -Encoding utf8

$md = @"
# 课上接口清单（课堂/白板 Web 应用 + 实时快照）

- 抓取时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- 课堂: teacherClassId=623589057 cid=623589060 (27考研专业课一对一, uid=25527722)
- 来源:
  - 课堂页实时 XHR 快照（直播 Web 应用: assets.coursebox.xdf.cn/wb/<hash>/）
  - bundle 提取: js_wb/(白板主应用), js_wbtools/(点名/抢答/签到等互动工具), js_sdk/(wbSdk, im.sdk)
- 认证: 与主应用同为 JWT(token=), 另有课堂上下文参数 (cid/teacherClassId/identity=3 学生)

## 一、实时 XHR 快照（课上实际请求, token 已打码）
$(($snap.xhr | ForEach-Object { Redact $_ } | Sort-Object -Unique) -join "`n")

## 二、bundle 提取的接口路径
$(($apiPaths | Sort-Object) -join "`n")

## 三、WebSocket / 信令
- 入口: https://im.roombox.xdf.cn/polaris/v1/ws_servers （返回可连的 WS 服务器列表）
- 模板: $(($wsUrls | Sort-Object) -join "`n")

## 四、域名
$(($domains | Sort-Object) -join "`n")

## 五、说明
- 路径模板中 ``{}`` 为占位符（源码里的模板变量）
- 快照内含 ``_mode=dev`` 等源生参数, 属应用自身行为, 照常携带即可
- 互动工具(wbtools)为独立子应用: 随机点名/抢答/红包/签到(sign-in)等
"@
$md | Out-File "$OutDir\endpoints_classroom.md" -Encoding utf8
Log ("已保存: endpoints_classroom.md / endpoints_classroom_raw.json")
