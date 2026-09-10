using System;
using System.IO;
using Lumen.Configuration;

namespace Lumen.Detection;

/// <summary>
/// Detects live agent sessions by watching their session-log files for recent
/// writes, per <c>shared/detection.md</c>:
/// <list type="bullet">
///   <item>Claude Code: <c>%USERPROFILE%\.claude\projects\**\*.jsonl</c></item>
///   <item>Codex: <c>%USERPROFILE%\.codex\sessions\**\*.jsonl</c></item>
/// </list>
/// </summary>
public sealed class SessionMonitor
{
    private readonly string _claudeDir;
    private readonly string _codexDir;

    public SessionMonitor()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(home))
            home = Environment.GetEnvironmentVariable("USERPROFILE") ?? string.Empty;

        _claudeDir = Path.Combine(home, ".claude", "projects");
        _codexDir = Path.Combine(home, ".codex", "sessions");
    }

    /// <summary>
    /// Returns true if any watched session log was modified within
    /// <c>graceMinutes</c>. Short-circuits on the first recent file found.
    /// </summary>
    public bool IsSessionActive(AppConfig config)
    {
        DateTime cutoffUtc = DateTime.UtcNow.AddMinutes(-config.GraceMinutes);

        if (config.WatchClaude && HasRecentJsonl(_claudeDir, cutoffUtc))
            return true;

        if (config.WatchCodex && HasRecentJsonl(_codexDir, cutoffUtc))
            return true;

        return false;
    }

    private static bool HasRecentJsonl(string root, DateTime cutoffUtc)
    {
        if (string.IsNullOrEmpty(root) || !Directory.Exists(root))
            return false;

        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
        };

        try
        {
            foreach (string file in Directory.EnumerateFiles(root, "*.jsonl", options))
            {
                try
                {
                    if (File.GetLastWriteTimeUtc(file) >= cutoffUtc)
                        return true;
                }
                catch
                {
                    // File vanished mid-scan or is locked; ignore and continue.
                }
            }
        }
        catch
        {
            // Enumeration failed entirely; treat as no activity.
        }

        return false;
    }
}
