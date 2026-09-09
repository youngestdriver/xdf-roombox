using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using XdfRoombox.Models;

namespace XdfRoombox.Services;

/// <summary>Chrome DevTools Protocol 客户端（连接云教室的 CEF 调试端口）</summary>
public class CdpClient
{
    private readonly int _port;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(5) };

    public CdpClient(int port) => _port = port;

    private string BaseUrl => $"http://127.0.0.1:{_port}";

    /// <summary>列出全部调试目标；端口未就绪返回 null</summary>
    public async Task<List<CdpTarget>?> GetTargetsAsync()
    {
        try
        {
            var json = await Http.GetStringAsync($"{BaseUrl}/json");
            return JsonSerializer.Deserialize<List<CdpTarget>>(json) ?? new();
        }
        catch { return null; }
    }

    /// <summary>浏览器级 WebSocket 地址（用于 Target.createTarget / closeTarget）</summary>
    public async Task<string?> GetBrowserWsAsync()
    {
        try
        {
            var json = await Http.GetStringAsync($"{BaseUrl}/json/version");
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.TryGetProperty("webSocketDebuggerUrl", out var v) ? v.GetString() : null;
        }
        catch { return null; }
    }

    /// <summary>在页面上执行 JS 并返回结果字符串</summary>
    public async Task<string?> EvaluateAsync(string wsUrl, string expression, int timeoutMs = 10000)
    {
        var resp = await SendAsync(wsUrl, new
        {
            id = 1,
            method = "Runtime.evaluate",
            @params = new { expression, returnByValue = true, awaitPromise = true }
        }, timeoutMs);
        if (resp == null) return null;
        try
        {
            var root = resp.Value;
            if (root.TryGetProperty("result", out var result))
            {
                if (result.TryGetProperty("exceptionDetails", out var ex))
                    return "EXC: " + ex.GetProperty("exceptionDetails").GetProperty("description").GetString();
                if (result.TryGetProperty("result", out var r) && r.TryGetProperty("value", out var val))
                    return val.ValueKind == JsonValueKind.String ? val.GetString() : val.ToString();
            }
            return null;
        }
        catch { return null; }
    }

    /// <summary>新建标签页，返回 targetId</summary>
    public async Task<string?> CreateTargetAsync(string url)
    {
        var bws = await GetBrowserWsAsync();
        if (bws == null) return null;
        var resp = await SendAsync(bws, new { id = 1, method = "Target.createTarget", @params = new { url } });
        try { return resp?.GetProperty("result").GetProperty("targetId").GetString(); }
        catch { return null; }
    }

    /// <summary>关闭标签页</summary>
    public async Task<bool> CloseTargetAsync(string targetId)
    {
        var bws = await GetBrowserWsAsync();
        if (bws == null) return false;
        var resp = await SendAsync(bws, new { id = 1, method = "Target.closeTarget", @params = new { targetId } });
        try { return resp?.GetProperty("result").GetProperty("success").GetBoolean() ?? false; }
        catch { return false; }
    }

    private static async Task<JsonElement?> SendAsync(string wsUrl, object payload, int timeoutMs = 10000)
    {
        using var cts = new CancellationTokenSource(timeoutMs);
        using var ws = new ClientWebSocket();
        try
        {
            await ws.ConnectAsync(new Uri(wsUrl), cts.Token);
            var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(payload));
            await ws.SendAsync(bytes, WebSocketMessageType.Text, true, cts.Token);

            var buffer = new byte[8 * 1024 * 1024];
            var sb = new StringBuilder();
            WebSocketReceiveResult result;
            do
            {
                result = await ws.ReceiveAsync(buffer, cts.Token);
                sb.Append(Encoding.UTF8.GetString(buffer, 0, result.Count));
            } while (!result.EndOfMessage);

            return JsonDocument.Parse(sb.ToString()).RootElement.Clone();
        }
        catch { return null; }
    }
}
