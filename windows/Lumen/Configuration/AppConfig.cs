using System.Collections.Generic;

namespace Lumen.Configuration;

/// <summary>
/// User-facing configuration. Persisted to <c>%APPDATA%\Lumen\config.json</c>.
/// Keys and defaults mirror <c>shared/detection.md</c> exactly so behaviour is
/// identical across platforms.
/// </summary>
public sealed class AppConfig
{
    // --- shared/detection.md schema keys ---

    /// <summary>Keep awake this long after last activity (minutes).</summary>
    public int GraceMinutes { get; set; } = 10;

    /// <summary>Below this level on battery → allow sleep (percent).</summary>
    public int BatteryFloorPercent { get; set; } = 20;

    /// <summary>Below this level on battery → force sleep (percent).</summary>
    public int CriticalBatteryPercent { get; set; } = 10;

    /// <summary>Hard cap on continuous awake time (hours). 0 = no cap.</summary>
    public int MaxHours { get; set; } = 8;

    /// <summary>CPU bar for process triggers (percent).</summary>
    public int CpuThresholdPercent { get; set; } = 40;

    /// <summary>Only keep awake while on the charger.</summary>
    public bool AcOnly { get; set; } = false;

    /// <summary>Use the process list as an activity trigger.</summary>
    public bool EnableProcessTriggers { get; set; } = false;

    /// <summary>Executable names (without extension) to watch.</summary>
    public List<string> ProcessList { get; set; } = new();

    /// <summary>Watch Claude Code session logs.</summary>
    public bool WatchClaude { get; set; } = true;

    /// <summary>Watch Codex session logs.</summary>
    public bool WatchCodex { get; set; } = true;

    /// <summary>How often to evaluate (seconds).</summary>
    public int PollSeconds { get; set; } = 15;

    // --- Windows-specific additions ---

    /// <summary>
    /// When enabled, Lumen sets the Windows lid-close action to "Do nothing"
    /// while keep-awake is active (requires a one-time UAC prompt), and restores
    /// the previous value when it stops or on exit.
    /// </summary>
    public bool ManageLidPolicy { get; set; } = false;

    /// <summary>
    /// UI language override: <c>"en"</c>, <c>"ru"</c>, <c>"kk"</c>, or
    /// <c>null</c>/empty to follow the OS UI culture.
    /// </summary>
    public string? Language { get; set; } = null;

    /// <summary>Returns a defensive clone (used by the settings editor).</summary>
    public AppConfig Clone() => new()
    {
        GraceMinutes = GraceMinutes,
        BatteryFloorPercent = BatteryFloorPercent,
        CriticalBatteryPercent = CriticalBatteryPercent,
        MaxHours = MaxHours,
        CpuThresholdPercent = CpuThresholdPercent,
        AcOnly = AcOnly,
        EnableProcessTriggers = EnableProcessTriggers,
        ProcessList = new List<string>(ProcessList),
        WatchClaude = WatchClaude,
        WatchCodex = WatchCodex,
        PollSeconds = PollSeconds,
        ManageLidPolicy = ManageLidPolicy,
        Language = Language,
    };

    /// <summary>Clamps values into safe ranges after load or edit.</summary>
    public void Normalize()
    {
        GraceMinutes = Clamp(GraceMinutes, 1, 24 * 60);
        BatteryFloorPercent = Clamp(BatteryFloorPercent, 0, 100);
        CriticalBatteryPercent = Clamp(CriticalBatteryPercent, 0, 100);
        if (CriticalBatteryPercent > BatteryFloorPercent)
            CriticalBatteryPercent = BatteryFloorPercent;
        MaxHours = Clamp(MaxHours, 0, 72);
        CpuThresholdPercent = Clamp(CpuThresholdPercent, 1, 100);
        PollSeconds = Clamp(PollSeconds, 5, 600);
        ProcessList ??= new List<string>();
    }

    private static int Clamp(int value, int min, int max)
        => value < min ? min : (value > max ? max : value);
}
