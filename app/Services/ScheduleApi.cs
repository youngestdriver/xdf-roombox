using System.Net.Http;
using System.Text;
using System.Text.Json;
using XdfRoombox.Models;

namespace XdfRoombox.Services;

/// <summary>云教室 HTTP API 封装</summary>
public class ScheduleApi
{
    private const string ApiBase = "https://api.roombox.xdf.cn";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    /// <summary>解析 JWT payload（不验签，仅读 sub/exp）</summary>
    public static JwtInfo? ParseJwt(string token)
    {
        try
        {
            var parts = token.Split('.');
            if (parts.Length != 3) return null;
            var p = parts[1].Replace('-', '+').Replace('_', '/');
            p = p.PadRight(p.Length + (4 - p.Length % 4) % 4, '=');
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(p));
            return JsonSerializer.Deserialize<JwtInfo>(json);
        }
        catch { return null; }
    }

    /// <summary>拉取时间窗内的课表</summary>
    public static async Task<List<Lesson>> FetchLessonsAsync(string token, string uid, long fromSec, long toSec)
    {
        var url = $"{ApiBase}/api/schedule/my?userId={Uri.EscapeDataString(uid)}&queryType=1" +
                  $"&startDate={fromSec}&endDate={toSec}&token={Uri.EscapeDataString(token)}";
        try
        {
            var json = await Http.GetStringAsync(url);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.GetProperty("code").GetInt32() != 0) return new();
            var list = JsonSerializer.Deserialize<List<Lesson>>(root.GetProperty("data").GetRawText());
            return list ?? new();
        }
        catch { return new(); }
    }
}
