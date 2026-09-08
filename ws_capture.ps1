# 新东方云教室 — 捕获课堂页 WebSocket 连接/帧
# 原理: 通过 CDP 的 Network 域订阅 webSocketCreated / webSocketWillSendHandshakeRequest /
#       webSocketFrameSent / webSocketFrameReceived 事件; Now 模式用 Runtime.queryObjects
#       反查页面上已存在的 WebSocket 实例(补抓已建立的连接)。
# 用法: pwsh -File ws_capture.ps1 -Mode Now            # 立即列出课堂页当前所有 WS 连接
#       pwsh -File ws_capture.ps1 -Mode Watch -Seconds 300   # 监听 5 分钟(抓新连接+收发帧), 建议课前挂上
param(
  [ValidateSet('Now', 'Watch')][string]$Mode = 'Watch',
  [int]$Seconds = 300
)
$ErrorActionPreference = 'Continue'

function Log([string]$m) { Write-Output "$(Get-Date -Format 'HH:mm:ss')  $m" }

# ---- 找课堂页 target ----
$targets = Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json' -TimeoutSec 5
if ($targets -isnot [System.Array]) { $targets = @($targets) }
$wb = $targets | Where-Object { $_.type -eq 'page' -and $_.url -match 'assets\.coursebox\.xdf\.cn/wb' } | Select-Object -First 1
if (-not $wb) { Log '未找到课堂页 target(需要课堂中运行)'; exit 1 }
Log "课堂页: $($wb.title) id=$($wb.id)"
$WsUrl = $wb.webSocketDebuggerUrl

function New-Ws([string]$url) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  [void]$ws.ConnectAsync([Uri]$url, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
  return $ws
}
function Send-Cdp($ws, [string]$json) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
}
function Receive-Cdp($ws, [System.Threading.CancellationToken]$ct) {
  $buf = [byte[]]::new(8388608); $out = [System.Text.StringBuilder]::new()
  do {
    $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
    [void]$out.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
  } while (-not $r.EndOfMessage)
  return ($out.ToString() | ConvertFrom-Json)
}
function Decode-Payload([string]$b64) {
  try { $bytes = [System.Convert]::FromBase64String($b64) } catch { return "(b64 err) $($b64.Substring(0,[Math]::Min(40,$b64.Length)))" }
  $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
  $printable = ($txt -notmatch '[\x00-\x08\x0b\x0c\x0e-\x1f]')
  if ($printable) { return "text: " + $txt.Substring(0, [Math]::Min(400, $txt.Length)) }
  $hex = ($bytes[0..([Math]::Min(31, $bytes.Length-1))] | ForEach-Object { $_.ToString('x2') }) -join ' '
  return "binary($($bytes.Length)B): $hex ..."
}

# ================= Now: 反查当前已建立的 WS 实例 =================
if ($Mode -eq 'Now') {
  $ws = New-Ws $WsUrl
  try {
    Send-Cdp $ws (@{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = 'WebSocket.prototype' } } | ConvertTo-Json -Compress)
    $proto = Receive-Cdp $ws ([System.Threading.CancellationToken]::None)
    $oid = $proto.result.result.objectId
    if (-not $oid) { Log '取 WebSocket.prototype 失败'; exit 1 }
    Send-Cdp $ws (@{ id = 2; method = 'Runtime.queryObjects'; params = @{ prototypeObjectId = $oid } } | ConvertTo-Json -Compress)
    $objs = Receive-Cdp $ws ([System.Threading.CancellationToken]::None)
    $arrId = $objs.result.objects.objectId
    Send-Cdp $ws (@{ id = 3; method = 'Runtime.callFunctionOn'; params = @{ objectId = $arrId; functionDeclaration = 'function(){var out=[];this.forEach(function(w){try{out.push({url:String(w.url),readyState:w.readyState,protocol:String(w.protocol)})}catch(e){}});return out}'; returnByValue = $true } } | ConvertTo-Json -Compress)
    $r = Receive-Cdp $ws ([System.Threading.CancellationToken]::None)
    if ($r.result.result.value) {
      Log ("当前课堂页活跃 WebSocket: " + @($r.result.result.value).Count)
      $r.result.result.value | ForEach-Object {
        $state = switch ($_.readyState) { 0 { 'CONNECTING' } 1 { 'OPEN' } 2 { 'CLOSING' } 3 { 'CLOSED' } default { $_.readyState } }
        Log ("  [" + $state + "] " + $_.url + "  (protocol='" + $_.protocol + "')")
      }
    } else { Log '未发现 WebSocket 实例(或页面无连接)' }
  } finally { $ws.Dispose() }
  exit 0
}

# ================= Watch: 订阅 Network 事件流 =================
$ws = New-Ws $WsUrl
$cts = [System.Threading.CancellationTokenSource]::new()
$cts.CancelAfter([TimeSpan]::FromSeconds($Seconds))
try {
  Send-Cdp $ws (@{ id = 1; method = 'Network.enable' } | ConvertTo-Json -Compress)
  Log ("Network.enable 已发送, 监听 $Seconds 秒 (Ctrl+C 可提前结束)")
  while ($true) {
    $m = Receive-Cdp $ws $cts.Token
    switch -Regex ($m.method) {
      '^Network\.webSocketCreated$' {
        $p = $m.params
        Log ("CREATE  " + $p.url + "  (initiator=" + ($p.initiator.type -replace '\s+',' ') + ")")
      }
      '^Network\.webSocketWillSendHandshakeRequest$' {
        $p = $m.params
        Log ("HANDSHAKE " + $p.request.url)
        foreach ($h in $p.request.headers.PSObject.Properties) { Log ("    " + $h.Name + ": " + ([string]$h.Value -replace '[\r\n]+',' ')) }
      }
      '^Network\.webSocketFrameSent$' {
        $f = $m.params.response
        Log ("SEND  opcode=$($f.opcode) len=$($f.payloadData.Length) :: " + (Decode-Payload $f.payloadData))
      }
      '^Network\.webSocketFrameReceived$' {
        $f = $m.params.response
        Log ("RECV  opcode=$($f.opcode) len=$($f.payloadData.Length) :: " + (Decode-Payload $f.payloadData))
      }
      '^Network\.webSocketFrameError$' {
        Log ("ERR   " + $m.params.errorMessage)
      }
      '^Network\.webSocketClosed$' {
        Log ("CLOSE " + $m.params.code)
      }
    }
  }
} catch [System.OperationCanceledException] {
  Log '监听时间到, 结束'
} catch {
  Log ('退出: ' + $_.Exception.Message)
} finally {
  $ws.Dispose(); $cts.Dispose()
}
