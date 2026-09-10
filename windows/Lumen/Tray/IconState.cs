namespace Lumen.Tray;

/// <summary>Visual state of the tray icon (mirrors the macOS app).</summary>
public enum IconState
{
    /// <summary>Sleep is disabled right now (keeping awake).</summary>
    Awake,

    /// <summary>Watching; currently allowing sleep.</summary>
    Armed,

    /// <summary>Manual allow-sleep.</summary>
    Paused,
}
