namespace Lumen.Configuration;

/// <summary>
/// The manual mode selected by the user. Mirrors the macOS CLI (auto/on/off/remote).
/// </summary>
public enum AppMode
{
    /// <summary>Follow session/process activity (default).</summary>
    Auto,

    /// <summary>Force keep-awake (still subject to safety governors).</summary>
    KeepAwake,

    /// <summary>Force allow-sleep. Overrides everything.</summary>
    AllowSleep,

    /// <summary>Remote working: behaves like <see cref="KeepAwake"/> on Windows.</summary>
    Remote,
}
