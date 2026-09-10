using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using Lumen.Detection;

namespace Lumen.Localization;

/// <summary>
/// Minimal JSON-backed localization. Loads <c>i18n/en.json</c> as the base and
/// overlays the selected language, so any missing key falls back to English and
/// then to the key itself. Default language follows the OS UI culture.
/// </summary>
public static class Strings
{
    private static readonly object Gate = new();
    private static Dictionary<string, string> _map = new(StringComparer.Ordinal);
    public static string CurrentLanguage { get; private set; } = "en";

    private static readonly string[] Supported = { "en", "ru", "kk" };

    /// <summary>
    /// (Re)load strings. <paramref name="preferred"/> is the config override
    /// (en/ru/kk) or null to follow the OS culture.
    /// </summary>
    public static void Load(string? preferred)
    {
        string lang = Resolve(preferred);
        string dir = Path.Combine(AppContext.BaseDirectory, "i18n");

        var merged = new Dictionary<string, string>(StringComparer.Ordinal);
        // Base: English.
        foreach (var kv in ReadFile(Path.Combine(dir, "en.json")))
            merged[kv.Key] = kv.Value;
        // Overlay: selected language (if not English).
        if (!string.Equals(lang, "en", StringComparison.Ordinal))
        {
            foreach (var kv in ReadFile(Path.Combine(dir, lang + ".json")))
                merged[kv.Key] = kv.Value;
        }

        lock (Gate)
        {
            _map = merged;
            CurrentLanguage = lang;
        }
    }

    /// <summary>Look up a key; returns the key itself if unknown.</summary>
    public static string Get(string key)
    {
        lock (Gate)
        {
            return _map.TryGetValue(key, out string? value) ? value : key;
        }
    }

    /// <summary>Look up and <see cref="string.Format(string, object?[])"/>.</summary>
    public static string Format(string key, params object?[] args)
    {
        string template = Get(key);
        try
        {
            return string.Format(CultureInfo.CurrentCulture, template, args);
        }
        catch (FormatException)
        {
            return template;
        }
    }

    /// <summary>Human-readable reason text for a decision.</summary>
    public static string Reason(DetectionResult result)
    {
        int pct = result.BatteryPercent ?? 0;
        return result.Reason switch
        {
            ReasonCode.ManualAllowSleep => Get("reason.manualAllowSleep"),
            ReasonCode.ManualKeepAwake => Get("reason.manualKeepAwake"),
            ReasonCode.Idle => Get("reason.idle"),
            ReasonCode.SessionActivity => Get("reason.sessionActivity"),
            ReasonCode.ProcessActivity => string.IsNullOrEmpty(result.Detail)
                ? Get("reason.processActivity")
                : Format("reason.processActivityNamed", result.Detail),
            ReasonCode.CriticalBattery => Format("reason.criticalBattery", pct),
            ReasonCode.BatteryFloor => Format("reason.batteryFloor", pct),
            ReasonCode.AcOnly => Get("reason.acOnly"),
            ReasonCode.Thermal => Get("reason.thermal"),
            ReasonCode.HardCap => Get("reason.hardCap"),
            ReasonCode.HardCapWaiting => Get("reason.hardCapWaiting"),
            _ => string.Empty,
        };
    }

    private static string Resolve(string? preferred)
    {
        if (!string.IsNullOrWhiteSpace(preferred))
        {
            string p = preferred.Trim().ToLowerInvariant();
            if (Array.IndexOf(Supported, p) >= 0)
                return p;
        }

        try
        {
            string osLang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.ToLowerInvariant();
            if (Array.IndexOf(Supported, osLang) >= 0)
                return osLang;
        }
        catch
        {
            // ignore and fall back
        }

        return "en";
    }

    private static Dictionary<string, string> ReadFile(string path)
    {
        try
        {
            if (!File.Exists(path))
                return new Dictionary<string, string>(StringComparer.Ordinal);
            string json = File.ReadAllText(path);
            var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
            return dict ?? new Dictionary<string, string>(StringComparer.Ordinal);
        }
        catch
        {
            return new Dictionary<string, string>(StringComparer.Ordinal);
        }
    }
}
