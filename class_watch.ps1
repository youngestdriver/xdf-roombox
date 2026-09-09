# 新东方云教室 — 全天课堂监听脚本
# 行为:
#   1) 上课前(15分钟内)/刚上课 自动进入教室
#   2) 课程规定时间结束 5 分钟后退出课堂(关闭课堂窗口)
#   3) 课后评价窗口自动提交(全选最左+提交, 不填意见)
#   4) 检测下一节"马上要上的课"(10分钟内开课), 自动进入下一个教室
# 依赖: 云教室以 --remote-debugging-port=9222 运行; 应用未运行时本脚本会自动带参数启动
# 用法:
#   pwsh -File class_watch.ps1 -Loop              # 常驻监控 (每30秒一轮)
#   pwsh -File class_watch.ps1 -CheckNow -DryRun  # 单轮演练(只报告不执行)
#   pwsh -File class_watch.ps1 -RestartIfNoDebug -Loop
param(
  [switch]$Loop,
  [switch]$CheckNow,
  [switch]$DryRun,
  [switch]$RestartIfNoDebug,
  [int]$ExitDelaySeconds = 300,        # 下课多少秒后退出课堂
  [int]$EnterAheadSeconds = 900,       # 提前多少秒进入教室(判定"马上要上")
  [int]$EnterGraceSeconds = 600,       # 开课后多少秒内仍可补进
  [int]$PollSeconds = 30,
  [string]$RoomBoxExe = 'D:\soft\XDF\Roombox\2.74.3.2063\Roombox.exe'
)
$ErrorActionPreference = 'Continue'
$Folder = $PSScriptRoot
if (-not $Folder) { $Folder = Split-Path -Parent $MyInvocation.MyCommand.Path }
$StateFile = Join-Path $Folder 'class_watch_state.json'
$LogFile   = Join-Path $Folder 'class_watch.log'

function Log([string]$m) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m"
  Write-Output $line
  Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
}
function Get-Epoch { return [DateTimeOffset]::Now.ToUnixTimeSeconds() }
function FromEpoch([long]$e) { return [DateTimeOffset]::FromUnixTimeSeconds($e).ToLocalTime() }

# ---------------- CDP 基础 ----------------
function Get-CdpTargets {
  try { $t = Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json' -TimeoutSec 3 } catch { return $null }
  if ($t -isnot [System.Array]) { $t = @($t) }
  return $t
}
function Get-BrowserWs {
  try { return (Invoke-RestMethod -Uri 'http://127.0.0.1:9222/json/version' -TimeoutSec 3).webSocketDebuggerUrl } catch { $null }
}
function Send-Cdp([string]$WsUrl, [string]$PayloadJson) {
  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  $ct = [System.Threading.CancellationToken]::None
  try {
    [void]$ws.ConnectAsync([Uri]$WsUrl, $ct).GetAwaiter().GetResult()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PayloadJson)
    [void]$ws.SendAsync([ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).GetAwaiter().GetResult()
    $buf = [byte[]]::new(8388608); $out = [System.Text.StringBuilder]::new()
    do {
      $r = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).GetAwaiter().GetResult()
      [void]$out.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Count))
    } while (-not $r.EndOfMessage)
    $resp = $out.ToString() | ConvertFrom-Json
    return $resp
  } catch { return $null } finally { $ws.Dispose() }
}
function Invoke-PageJs([string]$WsUrl, [string]$Expr) {
  $r = Send-Cdp $WsUrl (@{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Compress -Depth 8)
  if (-not $r) { return $null }
  if ($r.result.exceptionDetails) { return 'EXC: ' + $r.result.exceptionDetails.exception.description }
  return $r.result.result.value
}
function Close-Target([string]$targetId) {
  $bws = Get-BrowserWs
  if (-not $bws) { return $false }
  $r = Send-Cdp $bws (@{ id = 1; method = 'Target.closeTarget'; params = @{ targetId = $targetId } } | ConvertTo-Json -Compress)
  return ($r -and $r.result.success)
}

# ---------------- 数据 ----------------
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
function Get-Lessons([string]$token, [string]$uid) {
  $now = Get-Epoch
  $u = "https://api.roombox.xdf.cn/api/schedule/my?userId=$uid&queryType=1&startDate=$($now-10800)&endDate=$($now+21600)&token=$token"
  try { $r = Invoke-RestMethod -Uri $u -TimeoutSec 15 } catch { return $null }
  if ($r.code -ne 0) { return $null }
  return $r.data
}
function Read-State {
  if (Test-Path $StateFile) {
    try {
      $src = Get-Content $StateFile -Raw | ConvertFrom-Json
      $entered = @{}
      if ($src.entered) { foreach ($p in $src.entered.PSObject.Properties) { $entered[$p.Name] = $p.Value } }
      return [PSCustomObject]@{ entered = $entered; exited = @($src.exited); evaluated = @($src.evaluated) }
    } catch { }
  }
  return [PSCustomObject]@{ entered = @{}; exited = @(); evaluated = @() }
}
function Write-State($s) { $s | ConvertTo-Json -Depth 5 | Out-File $StateFile -Encoding utf8 }

# ---------------- 动作 ----------------
function Submit-Evaluation([object]$evalTarget, [string]$lessonId, $state) {
  Log "发现课后评价窗口(lesson=$lessonId), 自动提交(最左选项)"
  $expr = "(()=>{const groups=[...document.querySelectorAll('.evaluation-list')].slice(0,3);let c=0;groups.forEach(function(el){const f=el.querySelector('.option-item[data-option=`"1`"]');if(f){f.click();c++;}});const b=document.querySelector('.submit-btn');if(!b)return 'NOBTN groups='+c;b.classList.remove('disabled');b.click();return 'SUBMITTED groups='+c})()"
  $r = Invoke-PageJs $evalTarget.webSocketDebuggerUrl $expr
  Log "  提交: $r"
  Start-Sleep 6
  $after = Get-CdpTargets
  $stillOpen = $after | Where-Object { $_.type -eq 'page' -and $_.url -match '/comment/' } | Select-Object -First 1
  if (-not $stillOpen) {
    if ($lessonId -and ($state.evaluated -notcontains $lessonId)) { $state.evaluated += $lessonId }
    Log "  评价窗口已关闭 -> 提交成功"
  } else {
    Log "  窗口仍在(可能失败), 下轮重试"
  }
}

function Exit-Lesson([object]$lesson, $state, [object]$clsTarget) {
  Log "下课处理: [$($lesson.classroom_name)] 结束于 $((FromEpoch ([long]$lesson.end_time)).ToString('HH:mm')), 现在退出课堂"
  if ($DryRun) { Log "  [DRYRUN] 将关闭课堂窗口"; return }
  $ok = Close-Target $clsTarget.id
  Log "  closeTarget: $ok"
  if ($lesson.lesson_id -and ($state.exited -notcontains $lesson.lesson_id)) { $state.exited += $lesson.lesson_id }
}

function Enter-Lesson([object]$lesson, $state, $targets, [string]$uid) {
  $name = [string]$lesson.classroom_name
  $hhmm = (FromEpoch ([long]$lesson.start_time)).ToString('HH:mm')
  Log "进入教室: [$name] $((FromEpoch ([long]$lesson.start_time)).ToString('MM-dd HH:mm')) 开始"
  if ($DryRun) { Log "  [DRYRUN] 将点击「进入教室」"; return }

  # 确保有课表窗口
  $sched = $targets | Where-Object { $_.type -eq 'page' -and $_.url -like '*schedule*' } | Select-Object -First 1
  if (-not $sched) {
    $bws = Get-BrowserWs
    if (-not $bws) { Log "  无 browser ws, 跳过"; return }
    $u = "https://d.roombox.xdf.cn/schedule/?token=$($script:Token)&userid=$uid&servertime=$(Get-Epoch)&language=cn&theme=roomboxlight&version=2.74.3.2063&role=3"
    Send-Cdp $bws (@{ id = 1; method = 'Target.createTarget'; params = @{ url = $u } } | ConvertTo-Json -Compress) | Out-Null
    Start-Sleep 12
    $targets = Get-CdpTargets
    if (-not $targets) { Log "  课表窗口创建失败"; return }
    $sched = $targets | Where-Object { $_.type -eq 'page' -and $_.url -like '*schedule*' } | Select-Object -First 1
    if (-not $sched) { Log "  课表窗口加载超时"; return }
  }
  $nameJson = $name | ConvertTo-Json -Compress
  $expr = "(()=>{const name=$nameJson,hm='$hhmm';const all=[...document.querySelectorAll('button')].filter(b=>(b.textContent||'').includes('进入教室'));const bs=all.filter(b=>!((b.className||'').toString().includes('disabled')));if(!bs.length)return 'NOBUTTON all='+all.length;let hit=null;if(bs.length===1){hit=bs[0];}else{hit=bs.find(b=>{let el=b;for(let i=0;i<6&&el;i++){el=el.parentElement;if(el&&(el.innerText||'').includes(hm)&&(el.innerText||'').includes(name))return true;}return false;});}if(!hit)return 'AMBIG candidates='+bs.length+' all='+all.length;hit.click();return 'CLICKED cls='+hit.className})()"
  $r = Invoke-PageJs $sched.webSocketDebuggerUrl $expr
  Log "  点击结果: $r"
  if ("$r" -match '^CLICKED') {
    if ($lesson.lesson_id) { $state.entered[$lesson.lesson_id] = 'clicked' }
    Start-Sleep 15
    $after = Get-CdpTargets
    $newCls = $after | Where-Object { $_.type -eq 'page' -and $_.url -match 'assets\.coursebox\.xdf\.cn/wb' } | Select-Object -First 1
    if ($newCls) {
      if ($lesson.lesson_id) { $state.entered[$lesson.lesson_id] = 'done' }
      Log "  验证: 课堂窗口已打开 -> 进入成功"
    } else { Log "  验证: 未见课堂窗口(可能加载慢), 下轮复查" }
  }
}

# 清理课堂内权限类弹窗(摄像头/麦克风权限提示, 点取消)
function Clear-ClassroomDialogs([object]$clsTarget) {
  if ($DryRun) { return }
  $expr = "(()=>{const cands=[...document.querySelectorAll('button,div,a')].filter(function(e){var t=(e.innerText||'').trim();if(!t||t.length>20)return false;if(!/^(取消|知道了|确定|我知道了|关闭|确定退出)$/.test(t))return false;var p=e.parentElement;for(var i=0;i<6&&p;i++,p=p.parentElement){var pt=(p.innerText||'');if(/摄像头|麦克风|权限/.test(pt)&&pt.length<300)return true}return false});if(!cands.length)return 'NONE';cands[0].click();return 'CLICKED '+cands[0].innerText.trim()})()"
  $r = Invoke-PageJs $clsTarget.webSocketDebuggerUrl $expr
  if ("$r" -ne 'NONE') { Log "  课堂弹窗处理: $r" }
}

# 课前签到: 点击文本恰为「签到」的按钮 (签到后窗口消失, 幂等)
function Sign-In([object]$clsTarget) {
  if ($DryRun) { return }
  $r = Invoke-PageJs $clsTarget.webSocketDebuggerUrl '(()=>{const b=[...document.querySelectorAll("button")].find(function(x){return (x.innerText||"").trim()==="签到"});if(b){b.click();return "SIGNIN-CLICKED"}return "NONE"})()'
  if ("$r" -eq 'SIGNIN-CLICKED') { Log "  签到成功" }
}

# ---------------- 主检查 ----------------
function Invoke-Check {
  $targets = Get-CdpTargets
  if (-not $targets) {
    if (Get-Process -Name Roombox -ErrorAction SilentlyContinue) {
      if ($RestartIfNoDebug) {
        Log '云教室在运行但 9222 无响应, 自动重启...'
        Stop-Process -Name Roombox -Force -ErrorAction SilentlyContinue
        Start-Sleep 4
      } else { Log '云教室在运行但未开调试端口, 本次跳过 (用调试快捷方式启动或加 -RestartIfNoDebug)'; return }
    }
    Log '云教室未运行, 启动 --remote-debugging-port=9222'
    try { Start-Process -FilePath $RoomBoxExe -ArgumentList '--remote-debugging-port=9222' } catch {
      Log ('启动失败: ' + $_.Exception.Message); return
    }
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep 3; $targets = Get-CdpTargets; if ($targets) { break } }
    if (-not $targets) { Log '等待调试端口超时'; return }
  }

  # token
  $script:Token = $null; $uid = $null
  foreach ($p in @($targets)) {
    $t = Get-UrlParam $p.url 'token'
    if ($t) { $script:Token = $t; $uid = Get-UrlParam $p.url 'userid'; break }
  }
  if (-not $script:Token) { Log '未找到 token, 本次跳过'; return }
  if (-not $uid) { $uid = Get-JwtSub $script:Token }

  $lessons = Get-Lessons $script:Token $uid
  if (-not $lessons) { Log '课表接口失败, 本次跳过'; return }

  $clsTarget = $targets | Where-Object { $_.type -eq 'page' -and $_.url -match 'assets\.coursebox\.xdf\.cn/wb' } | Select-Object -First 1
  $evalTarget = $targets | Where-Object { $_.type -eq 'page' -and $_.url -match '/comment/' } | Select-Object -First 1
  $now = Get-Epoch
  $state = Read-State

  # A) 评价窗口处理 (优先级最高: 下课即弹, 提交后不影响课堂)
  if ($evalTarget) {
    $ended = @($lessons | Where-Object { ([long]$_.end_time) -le $now } | Sort-Object { [long]$_.end_time } -Descending | Select-Object -First 1)
    $forLesson = if ($ended) { $ended[0].lesson_id } else { '' }
    if (-not $forLesson -or ($state.evaluated -notcontains $forLesson)) {
      Submit-Evaluation $evalTarget $forLesson $state
    } else { Log '评价窗口已提交过, 跳过' }
  }

  # B) 下课检测: 课堂窗口存在 + 已结束课程超过 ExitDelay
  if ($clsTarget) {
    Clear-ClassroomDialogs $clsTarget
    Sign-In $clsTarget
    $endedNow = @($lessons | Where-Object { ([long]$_.end_time) -le $now -and (($now - [long]$_.end_time) -lt 10800) } | Sort-Object { [long]$_.end_time } -Descending | Select-Object -First 1)
    if ($endedNow) {
      $le = $endedNow[0]
      $over = $now - [long]$le.end_time
      if ($over -ge $ExitDelaySeconds) {
        if ($state.exited -notcontains $le.lesson_id) {
          Exit-Lesson $le $state $clsTarget
        } elseif ($clsTarget) {
          # 上次退出失败/窗口仍开: 幂等重关
          Log "课堂窗口仍存在(已标记退出), 重试关闭"
          if (-not $DryRun) { Close-Target $clsTarget.id | Out-Null }
        }
      } else {
        Log "课堂进行中: [$($le.classroom_name)] 下课还差 $([math]::Round(($ExitDelaySeconds-$over)/60, 1)) 分钟 (已结束 $([math]::Round($over/60,1)) 分钟)"
      }
    }
  } else {
    # C) 空闲: 检测"马上要上的课"并进入
    $next = @($lessons | Where-Object {
      $d = ([long]$_.start_time) - $now
      $d -ge (-$EnterGraceSeconds) -and $d -le $EnterAheadSeconds
    } | Sort-Object { [long]$_.start_time } | Select-Object -First 1)
    if ($next) {
      $n = $next[0]
      $entered = $state.entered[$n.lesson_id]
      if ($entered -eq 'done') {
        if ($clsTarget) { Log "下一课 [$($n.classroom_name)] 已进入过, 课堂窗口存在" }
        else {
          Log "已进入过 [$($n.classroom_name)] 但课堂窗口已关闭(手动退出/崩溃), 重新进入"
          Enter-Lesson $n $state $targets $uid
        }
      }
      elseif ($entered -eq 'clicked') {
        if (-not $clsTarget) { Log "已点击过 [$($n.classroom_name)] 但未见课堂窗口, 重新点击"; Enter-Lesson $n $state $targets $uid }
      }
      else { Enter-Lesson $n $state $targets $uid }
    } else { Log '空闲: 无临近课程' }
  }
  Write-State $state
}

Log "===== 全天课堂监听启动 (ExitDelay=${ExitDelaySeconds}s, EnterAhead=${EnterAheadSeconds}s, DryRun=$DryRun) ====="
if ($Loop -or -not $CheckNow) {
  while ($true) { Invoke-Check; Start-Sleep $PollSeconds }
} else {
  Invoke-Check
}
