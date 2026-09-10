namespace Lumen.Configuration;

/// <summary>
/// Persisted runtime state (mode + detection state machine + lid bookkeeping).
/// Kept separate from <see cref="AppConfig"/> so frequent state writes never
/// churn the user's settings file. Stored at <c>%APPDATA%\Lumen\state.json</c>.
/// </summary>
public sealed class AppState
{
    /// <summary>Current manual mode.</summary>
    public AppMode Mode { get; set; } = AppMode.Auto;

    /// <summary>
    /// Unix seconds when keep-awake first turned on for the current stretch,
    /// or null when idle. Used for the hard-cap governor.
    /// </summary>
    public long? OnSinceUnix { get; set; }

    /// <summary>
    /// Hard-cap latch: once the cap fires we stay asleep-allowed until a genuine
    /// idle period (no activity) clears it.
    /// </summary>
    public bool Capped { get; set; }

    /// <summary>
    /// If set, a timed keep-awake session ends at this Unix-seconds instant,
    /// after which the mode reverts to <see cref="AppMode.Auto"/>.
    /// </summary>
    public long? TimedUntilUnix { get; set; }

    // --- lid-policy bookkeeping (for crash-safe restore) ---

    /// <summary>True while Lumen has overridden the lid-close power policy.</summary>
    public bool LidManaged { get; set; }

    /// <summary>Previous AC lid action index to restore.</summary>
    public int? SavedLidAc { get; set; }

    /// <summary>Previous DC lid action index to restore.</summary>
    public int? SavedLidDc { get; set; }
}
