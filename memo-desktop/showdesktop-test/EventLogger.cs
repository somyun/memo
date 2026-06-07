using System.Text.Json;

namespace ShowDesktopTest;

internal sealed class EventLogger
{
    private readonly object _gate = new();

    public EventLogger()
    {
        var dir = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ShowDesktopTest");
        Directory.CreateDirectory(dir);
        Path = System.IO.Path.Combine(dir, "events.jsonl");
    }

    public string Path { get; }

    public void Clear()
    {
        lock (_gate)
        {
            File.WriteAllText(Path, string.Empty);
        }
    }

    public void Write(string type, object payload)
    {
        var line = JsonSerializer.Serialize(new
        {
            timestamp = DateTimeOffset.Now,
            type,
            payload
        });

        lock (_gate)
        {
            File.AppendAllText(Path, line + Environment.NewLine);
        }
    }
}
