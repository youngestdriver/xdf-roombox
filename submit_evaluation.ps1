# 课后评价 — 自动选第一档(最左)并提交
# 只操作"课后评价"窗口; 不填意见文本框; 提交走页面自身的 ajax(POST /api/comment/add)。
# 用法: pwsh -File submit_evaluation.ps1              # 立即: 找窗口->选择->提交->确认
#       pwsh -File submit_evaluation.ps1 -WaitMinutes 30   # 等窗口出现(课后自动弹出)再提交
param([int]$WaitMinutes = 0)
$ErrorActionPreference = 'Continue'

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
    if ($resp.result.exceptionDetails) { return ('EXC: ' + $resp.result.exceptionDetails.exception.description) }
    return $resp.result.result.value
  } catch { return 'ERR: ' + $_.Exception.Message } finally { $ws.Dispose() }
}

# 1) 找评价窗口 (可选等待)
$comment = $null
$deadline = (Get-Date).AddMinutes($WaitMinutes)
while ($true) {
  try { $targets = Get-Targets } catch { $targets = $null }
  if ($targets) {
    $comment = $targets | Where-Object { $_.type -eq 'page' -and $_.url -match '/comment/' } | Select-Object -First 1
  }
  if ($comment) { break }
  if ((Get-Date) -ge $deadline) { Log '未找到课后评价窗口(可能已关闭或未弹出)'; exit 1 }
  Log '等待课后评价窗口出现...'
  Start-Sleep 3
}
Log ("找到评价窗口: " + $comment.url.Substring(0, [Math]::Min(90, $comment.url.Length)) + "...")

# 2) 页面里: 每组选第一项(最左) + 点提交 (不动 textarea)
$expr = "(()=>{const groups=[...document.querySelectorAll('.evaluation-list')].slice(0,3);let clicked=0;groups.forEach(function(el){const first=el.querySelector('.option-item[data-option=`"1`"]');if(first){first.click();clicked++;}});const btn=document.querySelector('.submit-btn');if(!btn)return 'NO-SUBMIT-BTN groups='+clicked;btn.classList.remove('disabled');btn.click();return 'CLICKED groups='+clicked+' -> SUBMIT'})()"
$r = Invoke-PageJs $comment.webSocketDebuggerUrl $expr
Log ("执行结果: " + $r)

# 3) 验证: 成功路径 code=200 -> toast -> 1秒后原生桥关闭窗口
Start-Sleep 4
$gone = $true
try {
  $targets2 = Get-Targets
  if ($targets2 | Where-Object { $_.type -eq 'page' -and $_.url -match '/comment/' }) { $gone = $false }
} catch { }
if ($gone) {
  Log '✅ 评价窗口已关闭 -> 提交成功(窗口由原生层关闭, 说明 code=200 流程走完)'
} else {
  Log '⚠ 窗口仍在(提交可能失败: token 失效 code=21012 或网络错误), 可重跑本脚本或手动处理'
}
