namespace Lumen.Detection;

/// <summary>
/// A machine-readable reason for the current decision. The UI layer maps these
/// to localized human-readable strings.
/// </summary>
public enum ReasonCode
{
    /// <summary>Manual "allow sleep" override.</summary>
    ManualAllowSleep,

    /// <summary>Manual "keep awake" / remote override.</summary>
    ManualKeepAwake,

    /// <summary>No activity — normal sleep allowed.</summary>
    Idle,

    /// <summary>A watched session log was written recently.</summary>
    SessionActivity,

    /// <summary>A watched process is using sustained CPU.</summary>
    ProcessActivity,

    /// <summary>Critical battery on battery power — forced sleep.</summary>
    CriticalBattery,

    /// <summary>Below the battery floor on battery power.</summary>
    BatteryFloor,

    /// <summary>AC-only mode and currently on battery.</summary>
    AcOnly,

    /// <summary>Thermal pressure is high.</summary>
    Thermal,

    /// <summary>Continuous awake time reached the hard cap.</summary>
    HardCap,

    /// <summary>Hard cap latched — waiting for an idle period to re-arm.</summary>
    HardCapWaiting,
}
