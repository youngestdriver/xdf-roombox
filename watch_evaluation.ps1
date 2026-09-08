# 课后评价窗口监听器 — 发现弹出时自动抓取 页面信息+实时XHR+脚本清单
# 只观察, 不点击/不提交。
# 用法: pwsh -File watch_evaluation.ps1    (默认挂 12 分钟; 发现评价窗口后多收集 60 秒再结束)
param([int]$Minutes = 12)
$ErrorActionPreference = 'Continue'
$OutFile = "$PSScriptRoot\evaluation_capture.json"

function Log([string]$m) { Write-Output "$(Get-Date -Format 'HH:mm:ss')  $m" }
function Get-Targets {
  $t = Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json' -TimeoutSec 3
  if ($t -isnot [System.Array]) { $t = @($t) }
  return $t
}
function Invoke-PageJs([string]$WsUrl, [string]$Expr) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ct = [System.Threading.CancellationToken]::None
  try {
    [void]$ws.ConnectAsync([Uri]$WsUrl, $ct).GetAwaiter().GetResult()
    $payload = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expr; returnByValue = $true } } | ConvertTo-Json -Compress -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
    $buf = [byte[]]::new(8388608); $out = [System.Text.StringBuilder]::new()
    do {
      $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
      [void]$out.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
    } while (-not $r.EndOfMessage)
    $resp = $out.ToString() | ConvertFrom-Json
    if ($resp.result.exceptionDetails) { return '' }
    return $resp.result.result.value
  } catch { return '' } finally { $ws.Dispose() }
}
function Snapshot-Target($tgt) {
  $val = Invoke-PageJs $tgt.webSocketDebuggerUrl 'JSON.stringify({title:document.title,body:(document.body?document.body.innerText.slice(0,2500):""),xhr:performance.getEntriesByType("resource").filter(e=>["xmlhttprequest","fetch"].indexOf(e.initiatorType)>=0).map(e=>e.name),scripts:[...document.querySelectorAll("script[src]")].map(s=>s.src)})'
  $obj = $null
  if ($val -and $val.StartsWith('{')) { try { $obj = $val | ConvertFrom-Json } catch {} }
  return [ordered]@{
    captured_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    target_id = $tgt.id
    title = $tgt.title
    url = $tgt.url
    body = if ($obj) { $obj.body } else { '' }
    xhr = if ($obj) { $obj.xhr } else { @() }
    scripts = if ($obj) { $obj.scripts } else { @() }
  }
}
function Save-Captures([array]$arr) {
  $arr | ConvertTo-Json -Depth 6 | Out-File $OutFile -Encoding utf8
}

Log "开始监听 (最多 $Minutes 分钟), 输出: $OutFile"
$seen = [System.Collections.Generic.HashSet[string]]::new()
$captured = @()
$evalFound = $false
$iterations = [math]::Floor($Minutes * 60 / 5)
for ($i = 0; $i -lt $iterations; $i++) {
  try { $targets = Get-Targets } catch { $targets = $null; Start-Sleep 5; continue }
  if (-not $targets) { Start-Sleep 5; continue }
  foreach ($tgt in @($targets) | Where-Object { $_.type -eq 'page' }) {
    if ($seen.Add($tgt.id)) {
      $snap = Snapshot-Target $tgt
      $captured += $snap
      Save-Captures $captured
      $kw = ($tgt.url + $tgt.title + $snap.body)
      $isEval = $kw -match '评价|问卷|feedback|evaluate|comment|rating'
      Log ("[新窗口] " + $tgt.title + ($(if ($isEval) { '  <== 疑似评价窗口' } else { '' })) + " :: body前80字: " + $snap.body.Substring(0,[Math]::Min(80,$snap.body.Length)))
      if ($isEval) { $evalFound = $true }
    } else {
      # 已有页面: 每5秒扫一眼正文, 捕捉以弹窗形式出现的情况
      $txt = Invoke-PageJs $tgt.webSocketDebuggerUrl '(document.body?document.body.innerText:"")'
      if ($txt -and $txt -match '课后评价|课程评价|评价课程|满意度') {
        $snap = Snapshot-Target $tgt
        $captured += $snap
        Save-Captures $captured
        Log ("[弹窗出现] " + $tgt.title + " :: " + $snap.body.Substring(0,[Math]::Min(120,$snap.body.Length)))
        $evalFound = $true
      }
    }
  }
  if ($evalFound) { Log '已发现评价窗口, 再收集 60 秒收尾'; Start-Sleep 60; break }
  Start-Sleep 5
}
Log ('结束. 共捕获 ' + $captured.Count + ' 个窗口快照 → ' + $OutFile)
