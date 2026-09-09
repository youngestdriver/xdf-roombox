using System.Text.Json.Serialization;

namespace XdfRoombox.Models;

/// <summary>课程讲次（对应云教室 schedule/my 与 class/lessons 的返回项）</summary>
public class Lesson
{
    [JsonPropertyName("lesson_id")] public string LessonId { get; set; } = "";
    [JsonPropertyName("classroom_name")] public string ClassroomName { get; set; } = "";
    [JsonPropertyName("start_time")] public string StartTimeRaw { get; set; } = "0";
    [JsonPropertyName("end_time")] public string EndTimeRaw { get; set; } = "0";
    [JsonPropertyName("room_code")] public string RoomCode { get; set; } = "";
    [JsonPropertyName("mainId")] public long MainId { get; set; }
    [JsonPropertyName("record")] public int Record { get; set; }
    [JsonPropertyName("teacher")] public TeacherInfo? Teacher { get; set; }
    [JsonPropertyName("playback")] public PlaybackInfo? Playback { get; set; }

    [JsonIgnore] public long StartTime => long.TryParse(StartTimeRaw, out var v) ? v : 0;
    [JsonIgnore] public long EndTime => long.TryParse(EndTimeRaw, out var v) ? v : 0;
    [JsonIgnore] public string TeacherName => Teacher?.TeacherName ?? "";
    [JsonIgnore] public DateTime StartLocal => DateTimeOffset.FromUnixTimeSeconds(StartTime).ToLocalTime().DateTime;
    [JsonIgnore] public DateTime EndLocal => DateTimeOffset.FromUnixTimeSeconds(EndTime).ToLocalTime().DateTime;

    public override string ToString() => $"[{StartLocal:MM-dd HH:mm}] {ClassroomName}";
}

public class TeacherInfo
{
    [JsonPropertyName("teacherName")] public string TeacherName { get; set; } = "";
}

public class PlaybackInfo
{
    [JsonPropertyName("status")] public int Status { get; set; }
    [JsonPropertyName("urls")] public List<string> Urls { get; set; } = new();
    [JsonPropertyName("mediaIds")] public List<string> MediaIds { get; set; } = new();
}

public class JwtInfo
{
    [JsonPropertyName("sub")] public string Sub { get; set; } = "";
    [JsonPropertyName("exp")] public long Exp { get; set; }
    [JsonPropertyName("iat")] public long Iat { get; set; }
    [JsonIgnore] public DateTime ExpLocal => DateTimeOffset.FromUnixTimeSeconds(Exp).ToLocalTime().DateTime;
}

/// <summary>CDP 调试目标</summary>
public class CdpTarget
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("url")] public string Url { get; set; } = "";
    [JsonPropertyName("webSocketDebuggerUrl")] public string WebSocketDebuggerUrl { get; set; } = "";
}

/// <summary>应用配置（持久化到 JSON）</summary>
public class AppConfig
{
    public string RoomboxExe { get; set; } = @"D:\soft\XDF\Roombox\2.74.3.2063\Roombox.exe";
    public int DebugPort { get; set; } = 9222;

    // 自动化开关
    public bool AutoEnter { get; set; } = true;
    public bool AutoSignIn { get; set; } = true;
    public bool AutoExit { get; set; } = true;
    public bool AutoEvaluate { get; set; } = true;

    // 时间参数
    public int EnterAheadSeconds { get; set; } = 900;    // 提前多久进入
    public int EnterGraceSeconds { get; set; } = 600;    // 开课后多久内仍可进
    public int ExitDelaySeconds { get; set; } = 300;     // 下课后多久退出
    public int PollSeconds { get; set; } = 30;           // 轮询间隔

    // 评价选项: 每组选第几项 (1=最左/最好)
    public int EvaluateOption { get; set; } = 1;
    public string EvaluateComment { get; set; } = "";    // 意见文本, 空=不填

    public bool StartMinimized { get; set; } = false;
}

/// <summary>日志条目</summary>
public class LogEntry
{
    public DateTime Time { get; set; } = DateTime.Now;
    public string Level { get; set; } = "INFO";
    public string Message { get; set; } = "";
    public override string ToString() => $"{Time:HH:mm:ss}  {Message}";
}

/// <summary>应用运行状态</summary>
public class RuntimeState
{
    public bool RoomboxRunning { get; set; }
    public bool DebugPortReady { get; set; }
    public string Token { get; set; } = "";
    public string Uid { get; set; } = "";
    public long TokenExp { get; set; }
    public Lesson? CurrentLesson { get; set; }      // 正在上的课
    public Lesson? NextLesson { get; set; }         // 下一节课
    public bool InClassroom { get; set; }           // 课堂窗口是否打开
    public bool SignedIn { get; set; }
    public string LastAction { get; set; } = "";
    public DateTime LastTick { get; set; } = DateTime.MinValue;
}
