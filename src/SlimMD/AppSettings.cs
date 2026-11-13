using System.Text.Json;

namespace SlimMD;

/// <summary>Persisted user preferences (language, window placement, last folder).</summary>
internal sealed class AppSettings
{
    public string Language { get; set; } = "en";
    public int X { get; set; } = -1;
    public int Y { get; set; } = -1;
    public int Width { get; set; } = 1100;
    public int Height { get; set; } = 760;
    public bool Maximized { get; set; }
    public string LastDirectory { get; set; } = "";

    private static string DirectoryPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SlimMD");

    public static string FilePath => Path.Combine(DirectoryPath, "settings.json");

    /// <summary>Diagnostic logging, enabled with SLIMMD_DEBUG=1.</summary>
    public static void DebugLog(string message)
    {
        if (Environment.GetEnvironmentVariable("SLIMMD_DEBUG") != "1") return;
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            File.AppendAllText(Path.Combine(DirectoryPath, "debug.log"),
                $"{DateTime.Now:HH:mm:ss.fff} {message}{Environment.NewLine}");
        }
        catch
        {
            // ignore
        }
    }

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var s = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath));
                if (s != null) return s;
            }
        }
        catch
        {
            // Corrupt settings must never prevent startup.
        }

        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // Ignore - preferences are non-critical.
        }
    }
}
