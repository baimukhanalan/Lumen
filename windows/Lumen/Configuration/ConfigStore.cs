using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Lumen.Configuration;

/// <summary>
/// Loads and saves <see cref="AppConfig"/> and <see cref="AppState"/> as JSON
/// under <c>%APPDATA%\Lumen\</c>. All I/O is defensive: a missing or corrupt
/// file falls back to defaults rather than throwing.
/// </summary>
public static class ConfigStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    /// <summary><c>%APPDATA%\Lumen</c>, created if missing.</summary>
    public static string DataDirectory
    {
        get
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string dir = Path.Combine(appData, "Lumen");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string ConfigPath => Path.Combine(DataDirectory, "config.json");
    public static string StatePath => Path.Combine(DataDirectory, "state.json");

    // --- config ---

    public static AppConfig LoadConfig()
    {
        AppConfig config = ReadOrDefault<AppConfig>(ConfigPath) ?? new AppConfig();
        config.Normalize();
        // Ensure a file exists on first run so users can find/edit it.
        if (!File.Exists(ConfigPath))
            SaveConfig(config);
        return config;
    }

    public static void SaveConfig(AppConfig config)
    {
        config.Normalize();
        WriteAtomic(ConfigPath, config);
    }

    // --- state ---

    public static AppState LoadState()
        => ReadOrDefault<AppState>(StatePath) ?? new AppState();

    public static void SaveState(AppState state)
        => WriteAtomic(StatePath, state);

    // --- helpers ---

    private static T? ReadOrDefault<T>(string path) where T : class
    {
        try
        {
            if (!File.Exists(path))
                return null;
            string json = File.ReadAllText(path);
            if (string.IsNullOrWhiteSpace(json))
                return null;
            return JsonSerializer.Deserialize<T>(json, Options);
        }
        catch
        {
            // Corrupt file → fall back to defaults rather than crashing the app.
            return null;
        }
    }

    private static void WriteAtomic<T>(string path, T value)
    {
        try
        {
            string json = JsonSerializer.Serialize(value, Options);
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, json);
            // Replace atomically where possible.
            if (File.Exists(path))
                File.Replace(tmp, path, null);
            else
                File.Move(tmp, path);
        }
        catch
        {
            // Best-effort persistence; never let a write failure crash the app.
        }
    }
}
