# 新东方云教室 — 自动进教室脚本
# 上课前 5 分钟自动在课表 Web 页面点击「进入教室」。
# 依赖: 云教室以 --remote-debugging-port=9222 启动（应用未运行时本脚本会自动按此方式启动它）。
#
# 用法:
#   powershell -File auto_enter.ps1 -Loop          # 常驻监控（推荐, 每30秒检查一次）
#   powershell -File auto_enter.ps1 -CheckNow      # 只检查一次（可配 -DryRun 演练）
#   powershell -File auto_enter.ps1 -CheckNow -DryRun   # 演练: 只报告将要做什么, 不点击
#   powershell -File auto_enter.ps1 -RestartIfNoDebug -Loop  # 应用已运行但未开调试口时, 自动重启带调试口
param(
  [switch]$Loop,
  [switch]$CheckNow,
  [switch]$DryRun,
  [switch]$RestartIfNoDebug,
  [int]$LeadSeconds = 300,               # 提前 5 分钟
  [int]$PollSeconds = 30,
  [string]$RoomBoxExe = 'D:\soft\XDF\Roombox\2.74.3.2063\Roombox.exe'
)
$ErrorActionPreference = 'Continue'
$Folder = $PSScriptRoot
if (-not $Folder) { $Folder = Split-Path -Parent $MyInvocation.MyCommand.Path }
$StateFile = Join-Path $Folder 'auto_enter_state.json'
$LogFile   = Join-Path $Folder 'auto_enter.log'

function Log([string]$m) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"
  Write-Output $line
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}

function Get-CdpTargets {
  try { @(Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json' -TimeoutSec 3 | Where-Object { $_ }) } catch { $null }
}

function Get-BrowserWs {
  try { return (Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json/version' -TimeoutSec 3).webSocketDebuggerUrl } catch { $null }
}

function Send-Cdp([string]$WsUrl, [string]$PayloadJson) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ct = [System.Threading.CancellationToken]::None
  try {
    $ws.ConnectAsync([Uri]$WsUrl, $ct).GetAwaiter().GetResult()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PayloadJson)
    [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
    $buf = [byte[]]::new(8388608)
    $out = [System.Text.StringBuilder]::new()
    do {
      $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
      [void]$out.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
    } while (-not $r.EndOfMessage)
    return ($out.ToString() | ConvertFrom-Json)
  } catch { return $null } finally { $ws.Dispose() }
}

function Invoke-PageJs([string]$WsUrl, [string]$Expr) {
  $payload = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expr; returnByValue = $true; awaitPromise = $true } } |
    ConvertTo-Json -Compress -Depth 8
  $r = Send-Cdp $WsUrl $payload
  if (-not $r) { return $null }
  if ($r.result.exceptionDetails) { return 'EXC: ' + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value
}

function Get-UrlParam([string]$url, [string]$name) {
  $m = [regex]::Match($url, "[?&]$name=([^&]+)")
  if (-not $m.Success) { return $null }
  return [System.Net.WebUtility]::UrlDecode($m.Groups[1].Value)
}

function Get-JwtSub([string]$token) {
  try {
    $p = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
    return ((ConvertFrom-Json ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($p)))).sub)
  } catch { return $null }
}

function Read-State {
  if (Test-Path $StateFile) {
    try { $s = Get-Content $StateFile -Raw | ConvertFrom-Json; return @($s | Where-Object { $_ }) } catch { return @() }
  }
  return @()
}
function Write-State($state) {
  $state | ConvertTo-Json -Depth 5 | Out-File $StateFile -Encoding utf8
}

# ---- 单次检查 ----
function Invoke-Check {
  $targets = Get-CdpTargets
  if (-not $targets) {
    if (Get-Process -Name Roombox -ErrorAction SilentlyContinue) {
      if ($RestartIfNoDebug) {
        Log '云教室在运行但未开调试端口(9222), 自动重启...'
        Stop-Process -Name Roombox -Force -ErrorAction SilentlyContinue
        Start-Sleep 4
      } else {
        Log '云教室在运行但 9222 无响应(未带 --remote-debugging-port 启动), 本次跳过。修复: 退出后用 README 方式启动, 或加 -RestartIfNoDebug'
        return
      }
    }
    Log '云教室未运行, 启动: --remote-debugging-port=9222'
    try { Start-Process -FilePath $RoomBoxExe -ArgumentList '--remote-debugging-port=9222' } catch {
      Log ('启动失败: ' + $_.Exception.Message); return
    }
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep 3; $targets = Get-CdpTargets
      if ($targets) { break }
    }
    if (-not $targets) { Log '等待调试端口超时(120s)'; return }
    Log '调试端口就绪'
  }

  $pages = @($targets | Where-Object { $_.type -eq 'page' })
  $sched = $pages | Where-Object { $_.url -like '*schedule*' } | Select-Object -First 1

  # 1) 取 token: 优先课表页 URL, 其次任意页面 URL
  $token = $null; $uid = $null; $role = $null
  if ($sched) { $token = Get-UrlParam $sched.url 'token'; $uid = Get-UrlParam $sched.url 'userid'; $role = Get-UrlParam $sched.url 'role' }
  if (-not $token) {
    foreach ($p in $pages) { $t = Get-UrlParam $p.url 'token'; if ($t) { $token = $t; $uid = Get-UrlParam $p.url 'userid'; break } }
  }
  if (-not $token) { Log '未找到 token(可能停在登录页或页面未加载), 本次跳过'; return }
  if (-not $uid) { $uid = Get-JwtSub $token }
  if (-not $role) { $role = '3' }

  # 2) REST 拉课表 (查询窗: 12小时前 ~ 2天后)
  $now = [DateTimeOffset]::Now
  $startE = $now.AddHours(-12).ToUnixTimeSeconds()
  $endE = $now.AddDays(2).ToUnixTimeSeconds()
  $url = "https://api.roombox.xdf.cn/api/schedule/my?userId=$uid&queryType=1&startDate=$startE&endDate=$endE&token=$token"
  try { $resp = Invoke-RestMethod -Uri $url -TimeoutSec 15 } catch { Log ('课表接口失败: ' + $_.Exception.Message); return }
  if ($resp.code -ne 0) { Log ("课表接口返回 code=$($resp.code) msg=$($resp.msg)"); return }

  # 3) 找“临上课”的课: 开始时间在 [now-10min, now+LeadSeconds] 内的最近一节
  $due = @($resp.data | Where-Object {
      $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$_.start_time)
      $d = ($t - $now).TotalSeconds
      $d -le $LeadSeconds -and $d -gt -600
    } | Sort-Object { [long]$_.start_time })
  if (-not $due) { Log '当前无临近开课的课程'; return }

  $lesson = $due[0]
  $lstart = [DateTimeOffset]::FromUnixTimeSeconds([long]$lesson.start_time).ToLocalTime()
  $name = [string]$lesson.classroom_name
  $state = Read-State
  if ($state | Where-Object { $_.lesson_id -eq $lesson.lesson_id -and $_.status -match 'clicked|entered' }) {
    Log ("已自动进过本课(lesson=$($lesson.lesson_id) [$name]), 跳过"); return
  }
  Log ("临课: lesson=$($lesson.lesson_id) [$name] $($lstart.ToString('MM-dd HH:mm')) 开始, 差 $([math]::Round(($lstart - $now).TotalSeconds)) 秒")

  # 4) 已在课堂页则让位（避免重复进教室/顶掉当前课堂）
  $inClass = $pages | Where-Object { $_.url -match 'quickLive|classroom|/web/|/wb/|coursebox\.xdf\.cn/wb' -and $_.url -notlike '*schedule*' } | Select-Object -First 1
  if ($inClass) { Log '检测到已有课堂窗口, 本次不重复进入'; return }

  # 5) 保证有一个课表页 target（没有则新建一个）
  if (-not $sched) {
    $bws = Get-BrowserWs
    if (-not $bws) { Log '无法获取 browser ws'; return }
    $schedUrl = "https://d.roombox.xdf.cn/schedule/?token=$token&userid=$uid&servertime=$($now.ToUnixTimeSeconds())&language=cn&theme=roomboxlight&version=2.74.3.2063&role=$role"
    $r = Send-Cdp $bws (@{ id = 1; method = 'Target.createTarget'; params = @{ url = $schedUrl } } | ConvertTo-Json -Compress)
    if ($r -and $r.result.targetId) { Log ("新建课表窗口: " + $r.result.targetId) } else { Log '新建课表窗口失败' }
    Start-Sleep 12
    $targets = Get-CdpTargets
    if (-not $targets) { Log '新建窗口后目标列表为空'; return }
    $sched = @($targets | Where-Object { $_.type -eq 'page' -and $_.url -like '*schedule*' }) | Select-Object -First 1
    if (-not $sched) { Log '课表窗口加载超时, 本次跳过'; return }
  }

  # 6) 点击「进入教室」(DryRun 只报告)
  $nameJson = $name | ConvertTo-Json -Compress
  $hhmm = $lstart.ToString('HH:mm')
  $clickFn = 'hit.click();return "CLICKED@"+hm+" "+hit.className'
  if ($DryRun) { $clickFn = 'return "WOULD-CLICK@"+hm+" "+hit.className' }
  $expr = "(()=>{const name=$nameJson,hm='$hhmm';const all=[...document.querySelectorAll('button')].filter(b=>(b.textContent||'').includes('进入教室'));const bs=all.filter(b=>!((b.className||'').toString().includes('disabled')));if(!bs.length)return 'NOBUTTON all='+all.length;let hit=null;if(bs.length===1){hit=bs[0];}else{hit=bs.find(b=>{let el=b;for(let i=0;i<6&&el;i++){el=el.parentElement;if(el&&(el.innerText||'').includes(hm)&&(el.innerText||'').includes(name))return true;}return false;});}if(!hit)return 'AMBIG candidates='+bs.length+' all='+all.length;$clickFn})()"
  $beforeIds = @($targets | ForEach-Object { "$($_.id)|$($_.url)" })
  $result = Invoke-PageJs $sched.webSocketDebuggerUrl $expr
  Log ("点击结果: " + $result)
  if ($DryRun) { return }

  if ("$result" -notmatch '^CLICKED') {
    Log '未点击成功, 稍后重试'; return
  }
  # 标记状态（点击成功）
  $state = @(Read-State) + @(@{ lesson_id = $lesson.lesson_id; name = $name; start = $lesson.start_time; entered_at = (Get-Date).ToString('s'); status = 'clicked-unverified' })
  Write-State $state
  # 7) 验证: 课表页被导航走(进入教室)或出现新页面
  Start-Sleep 20
  $targets2 = Get-CdpTargets
  if ($targets2) {
    $afterIds = @($targets2 | ForEach-Object { "$($_.id)|$($_.url)" })
    $schedGone = -not (@($targets2 | Where-Object { $_.type -eq 'page' -and $_.url -like '*schedule*' }))
    $newPages = @($afterIds | Where-Object { $_ -notin $beforeIds -and $_ -match 'quickLive|classroom|/web/|/wb/|coursebox\.xdf\.cn/wb' })
    if ($schedGone -or $newPages) {
      Log '验证: 已离开课表页/出现课堂页 -> 进入教室成功'
      $st2 = @(Read-State | Where-Object { $_.lesson_id -ne $lesson.lesson_id }) + @(@{ lesson_id = $lesson.lesson_id; name = $name; start = $lesson.start_time; entered_at = (Get-Date).ToString('s'); status = 'entered' })
      Write-State $st2
    } else {
      Log '验证: 页面未见变化, 可能已在新课堂窗口进入(状态已保留)'
    }
  }
}

Log "===== 自动进教室脚本启动 (Lead=$($LeadSeconds)s, Poll=$($PollSeconds)s, DryRun=$DryRun) ====="
if ($Loop) {
  while ($true) { Invoke-Check; Start-Sleep $PollSeconds }
} else {
  Invoke-Check
}
