using System.IO;
using System.Text.Json;
using XdfRoombox.Models;

namespace XdfRoombox.Services;

/// <summary>核心状态机：进教室 / 签到 / 下课退出 / 评价提交 / 连堂</summary>
public class ClassWatcher
{
    private readonly AppConfig _cfg;
    private readonly CdpClient _cdp;
    private readonly RoomboxManager _roombox;
    private readonly Action<string, string> _log;

    // 每节课的处理状态（持久化，避免重复动作）
    private readonly Dictionary<string, string> _entered = new();
    private readonly HashSet<string> _exited = new();
    private readonly HashSet<string> _evaluated = new();
    private readonly string _statePath;

    public RuntimeState State { get; } = new();

    public ClassWatcher(AppConfig cfg, CdpClient cdp, RoomboxManager roombox, Action<string, string> log)
    {
        _cfg = cfg; _cdp = cdp; _roombox = roombox; _log = log;
        _statePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "XdfRoombox", "state.json");
        Directory.CreateDirectory(Path.GetDirectoryName(_statePath)!);
        LoadState();
    }

    /// <summary>单轮检查（由定时器每 PollSeconds 触发）</summary>
    public async Task TickAsync()
    {
        State.LastTick = DateTime.Now;
        State.RoomboxRunning = _roombox.IsRunning;

        // 1) 确保调试端口可用
        var targets = await _cdp.GetTargetsAsync();
        if (targets == null)
        {
            State.DebugPortReady = false;
            if (!State.RoomboxRunning)
            {
                _log("WARN", "云教室未运行，正在启动...");
                if (!_roombox.Start()) { _log("ERROR", "启动失败，请检查安装路径设置"); return; }
                if (!await _roombox.WaitForDebugPortAsync())
                {
                    _log("ERROR", "等待调试端口超时（请确认用调试模式启动）");
                    return;
                }
                _log("INFO", "云教室已启动，调试端口就绪");
                targets = await _cdp.GetTargetsAsync();
                if (targets == null) return;
            }
            else
            {
                State.LastAction = "云教室运行中但未开调试端口";
                return;
            }
        }
        State.DebugPortReady = true;

        // 2) 提取 token
        var pages = targets.Where(t => t.Type == "page").ToList();
        var schedPage = pages.FirstOrDefault(t => t.Url.Contains("/schedule/"));
        State.Token = ExtractParam(schedPage?.Url ?? pages.FirstOrDefault(t => t.Url.Contains("token="))?.Url, "token") ?? "";
        State.Uid = ExtractParam(schedPage?.Url, "userid") ?? "";
        if (string.IsNullOrEmpty(State.Token)) { State.LastAction = "未找到 token（等待登录）"; return; }
        if (string.IsNullOrEmpty(State.Uid)) State.Uid = ScheduleApi.ParseJwt(State.Token)?.Sub ?? "";
        State.TokenExp = ScheduleApi.ParseJwt(State.Token)?.Exp ?? 0;

        // 3) 拉课表（12h 前 ~ 6h 后）
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var lessons = await ScheduleApi.FetchLessonsAsync(State.Token, State.Uid, now - 43200, now + 21600);
        if (lessons.Count == 0 && State.TokenExp > 0 && now > State.TokenExp)
        {
            State.LastAction = "token 已过期";
            _log("WARN", "token 已过期，请重新登录云教室以刷新");
            return;
        }

        var classroom = pages.FirstOrDefault(t => t.Url.Contains("assets.coursebox.xdf.cn/wb"));
        var evalPage = pages.FirstOrDefault(t => t.Url.Contains("/comment/"));
        State.InClassroom = classroom != null;

        // 当前课/下一课（用于 UI 显示）
        State.CurrentLesson = lessons
            .Where(l => l.StartTime <= now && l.EndTime > now)
            .OrderBy(l => l.StartTime).FirstOrDefault();
        State.NextLesson = lessons
            .Where(l => l.StartTime > now)
            .OrderBy(l => l.StartTime).FirstOrDefault();

        // A) 评价窗口
        if (_cfg.AutoEvaluate && evalPage != null)
        {
            var ended = lessons.Where(l => l.EndTime <= now).OrderByDescending(l => l.EndTime).FirstOrDefault();
            var key = ended?.LessonId ?? "";
            if (string.IsNullOrEmpty(key) || !_evaluated.Contains(key))
            {
                await SubmitEvaluationAsync(evalPage, key);
                SaveState();
            }
        }

        // B) 课堂内：签到 + 权限弹窗清理
        if (classroom != null)
        {
            if (_cfg.AutoSignIn) await SignInAsync(classroom);
            await ClearDialogsAsync(classroom);

            State.LastAction = State.CurrentLesson != null
                ? $"课堂进行中：{State.CurrentLesson.ClassroomName}（{State.CurrentLesson.EndLocal:HH:mm} 结束）"
                : "课堂窗口已打开";

            // C) 下课退出
            if (_cfg.AutoExit)
            {
                var justEnded = lessons
                    .Where(l => l.EndTime <= now && now - l.EndTime < 10800)
                    .OrderByDescending(l => l.EndTime).FirstOrDefault();
                if (justEnded != null)
                {
                    var over = now - justEnded.EndTime;
                    if (over >= _cfg.ExitDelaySeconds)
                    {
                        if (!_exited.Contains(justEnded.LessonId))
                        {
                            _log("INFO", $"下课 {over / 60.0:F1} 分钟，退出课堂: {justEnded.ClassroomName}");
                            var closed = await QtDialogCloser.CloseClassroomAsync(_cdp, classroom.Id, _log);
                            if (closed)
                            {
                                _exited.Add(justEnded.LessonId);
                                State.LastAction = "已退出课堂";
                                _log("INFO", "  课堂已退出");
                                SaveState();
                            }
                            else _log("WARN", "  退出未完成，下轮重试");
                        }
                        else if (classroom != null)
                        {
                            await QtDialogCloser.CloseClassroomAsync(_cdp, classroom.Id, _log); // 幂等重关
                        }
                    }
                    else
                    {
                        State.LastAction = $"课堂进行中，{(_cfg.ExitDelaySeconds - over) / 60.0:F0} 分钟后退出";
                    }
                }
            }
        }
        else
        {
            // D) 空闲：检查是否要进下一节
            if (_cfg.AutoEnter)
            {
                var target = lessons
                    .Where(l => l.StartTime - now <= _cfg.EnterAheadSeconds && l.StartTime - now >= -_cfg.EnterGraceSeconds)
                    .OrderBy(l => l.StartTime).FirstOrDefault();
                if (target != null)
                {
                    var st = _entered.GetValueOrDefault(target.LessonId);
                    if (st == "done")
                    {
                        _log("INFO", $"「{target.ClassroomName}」已进入过但窗口不在，重新进入");
                        await EnterLessonAsync(target, schedPage);
                    }
                    else if (st != "clicked")
                    {
                        await EnterLessonAsync(target, schedPage);
                    }
                    else
                    {
                        State.LastAction = "已点击进入，等待课堂窗口...";
                    }
                }
                else State.LastAction = "空闲：无临近课程";
            }
        }
    }

    // ---------------- 动作 ----------------

    private async Task EnterLessonAsync(Lesson lesson, CdpTarget? schedPage)
    {
        _log("INFO", $"进入教室: {lesson.ClassroomName}（{lesson.StartLocal:MM-dd HH:mm} 开始）");
        if (schedPage == null)
        {
            var url = $"https://d.roombox.xdf.cn/schedule/?token={State.Token}&userid={State.Uid}" +
                      $"&servertime={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}&language=cn&theme=roomboxlight" +
                      $"&version=2.74.3.2063&role=3";
            var tid = await _cdp.CreateTargetAsync(url);
            if (tid == null) { _log("ERROR", "创建课表窗口失败"); return; }
            await Task.Delay(12000);
            var targets = await _cdp.GetTargetsAsync();
            schedPage = targets?.FirstOrDefault(t => t.Url.Contains("/schedule/"));
            if (schedPage == null) { _log("ERROR", "课表窗口加载超时"); return; }
        }

        var hhmm = lesson.StartLocal.ToString("HH:mm");
        var nameJson = JsonSerializer.Serialize(lesson.ClassroomName);
        var expr = "(()=>{const name=" + nameJson + ",hm='" + hhmm + "';" +
            "const all=[...document.querySelectorAll('button')].filter(b=>(b.textContent||'').includes('进入教室'));" +
            "const bs=all.filter(b=>!((b.className||'').toString().includes('disabled')));" +
            "if(!bs.length)return 'NOBUTTON all='+all.length;" +
            "let hit=null;if(bs.length===1){hit=bs[0];}" +
            "else{hit=bs.find(b=>{let el=b;for(let i=0;i<6&&el;i++){el=el.parentElement;" +
            "if(el&&(el.innerText||'').includes(hm)&&(el.innerText||'').includes(name))return true;}return false;});}" +
            "if(!hit)return 'AMBIG candidates='+bs.length+' all='+all.length;" +
            "hit.click();return 'CLICKED cls='+hit.className})()";
        var r = await _cdp.EvaluateAsync(schedPage.WebSocketDebuggerUrl, expr);
        _log("INFO", "  点击结果: " + r);
        if (r != null && r.StartsWith("CLICKED"))
        {
            _entered[lesson.LessonId] = "clicked";
            SaveState();
            await Task.Delay(15000);
            var after = await _cdp.GetTargetsAsync();
            if (after?.Any(t => t.Url.Contains("assets.coursebox.xdf.cn/wb")) == true)
            {
                _entered[lesson.LessonId] = "done";
                State.LastAction = $"已进入: {lesson.ClassroomName}";
                _log("INFO", "  验证: 课堂窗口已打开 -> 进入成功");
                SaveState();
            }
            else _log("WARN", "  验证: 未见课堂窗口，下轮重试");
        }
    }

    private async Task SignInAsync(CdpTarget classroom)
    {
        var r = await _cdp.EvaluateAsync(classroom.WebSocketDebuggerUrl,
            "(()=>{const b=[...document.querySelectorAll('button')].find(x=>(x.innerText||'').trim()==='签到');" +
            "if(b){b.click();return 'SIGNED'}return 'NONE'})()");
        if (r == "SIGNED")
        {
            State.SignedIn = true;
            State.LastAction = "已签到";
            _log("INFO", "签到成功");
        }
    }

    private async Task ClearDialogsAsync(CdpTarget classroom)
    {
        var r = await _cdp.EvaluateAsync(classroom.WebSocketDebuggerUrl,
            "(()=>{const c=[...document.querySelectorAll('button,div,a')].filter(e=>{" +
            "const t=(e.innerText||'').trim();if(!t||t.length>20)return false;" +
            "if(!/^(取消|知道了|确定|我知道了|关闭)$/.test(t))return false;" +
            "let p=e.parentElement;for(let i=0;i<6&&p;i++,p=p.parentElement){" +
            "const pt=(p.innerText||'');if(/摄像头|麦克风|权限/.test(pt)&&pt.length<300)return true}return false});" +
            "if(!c.length)return 'NONE';c[0].click();return 'CLEARED'})()");
        if (r == "CLEARED") _log("INFO", "已关闭权限提示弹窗");
    }

    private async Task SubmitEvaluationAsync(CdpTarget evalPage, string lessonId)
    {
        _log("INFO", "发现课后评价窗口，自动提交...");
        var opt = _cfg.EvaluateOption;
        var comment = JsonSerializer.Serialize(_cfg.EvaluateComment);
        var expr = "(()=>{const groups=[...document.querySelectorAll('.evaluation-list')].slice(0,3);" +
            "let c=0;groups.forEach(el=>{const f=el.querySelector('.option-item[data-option=\"" + opt + "\"]');if(f){f.click();c++}});" +
            "const ta=document.querySelector('textarea[name=advice]');if(ta)ta.value=" + comment + ";" +
            "const b=document.querySelector('.submit-btn');if(!b)return 'NOBTN groups='+c;" +
            "b.classList.remove('disabled');b.click();return 'SUBMITTED groups='+c})()";
        var r = await _cdp.EvaluateAsync(evalPage.WebSocketDebuggerUrl, expr);
        _log("INFO", "  提交: " + r);
        await Task.Delay(6000);
        var after = await _cdp.GetTargetsAsync();
        if (after?.Any(t => t.Url.Contains("/comment/")) != true)
        {
            if (!string.IsNullOrEmpty(lessonId)) _evaluated.Add(lessonId);
            State.LastAction = "评价已提交";
            _log("INFO", "  评价窗口已关闭 -> 提交成功");
            SaveState();
        }
        else _log("WARN", "  评价窗口仍在，下轮重试");
    }

    // ---------------- 辅助 ----------------

    private static string? ExtractParam(string? url, string name)
    {
        if (string.IsNullOrEmpty(url)) return null;
        var m = System.Text.RegularExpressions.Regex.Match(url, $"[?&]{name}=([^&]+)");
        return m.Success ? Uri.UnescapeDataString(m.Groups[1].Value) : null;
    }

    private void LoadState()
    {
        try
        {
            if (!File.Exists(_statePath)) return;
            using var doc = JsonDocument.Parse(File.ReadAllText(_statePath));
            var root = doc.RootElement;
            if (root.TryGetProperty("entered", out var e))
                foreach (var p in e.EnumerateObject()) _entered[p.Name] = p.Value.GetString() ?? "";
            if (root.TryGetProperty("exited", out var x))
                foreach (var v in x.EnumerateArray()) _exited.Add(v.GetString() ?? "");
            if (root.TryGetProperty("evaluated", out var v2))
                foreach (var v in v2.EnumerateArray()) _evaluated.Add(v.GetString() ?? "");
        }
        catch { }
    }

    private void SaveState()
    {
        try
        {
            var obj = new { entered = _entered, exited = _exited.ToArray(), evaluated = _evaluated.ToArray() };
            File.WriteAllText(_statePath, JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }
}
