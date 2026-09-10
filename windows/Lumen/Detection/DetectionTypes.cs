namespace Lumen.Detection;

/// <summary>Power state snapshot for the decision.</summary>
public readonly struct PowerInfo
{
    public PowerInfo(bool hasBattery, bool onBattery, int? percent)
    {
        HasBattery = hasBattery;
        OnBattery = onBattery;
        Percent = percent;
    }

    /// <summary>True if the machine has a battery at all (false on desktops).</summary>
    public bool HasBattery { get; }

    /// <summary>True if currently running on battery (not AC).</summary>
    public bool OnBattery { get; }

    /// <summary>Battery charge percent (0..100), or null if unknown.</summary>
    public int? Percent { get; }

    public static PowerInfo Desktop => new(hasBattery: false, onBattery: false, percent: null);
}

/// <summary>Thermal state snapshot (best-effort).</summary>
public readonly struct ThermalInfo
{
    public ThermalInfo(bool available, bool serious, double? maxCelsius)
    {
        Available = available;
        Serious = serious;
        MaxCelsius = maxCelsius;
    }

    /// <summary>Whether a thermal reading was obtainable.</summary>
    public bool Available { get; }

    /// <summary>Whether thermal pressure is Serious/Critical (should release).</summary>
    public bool Serious { get; }

    /// <summary>The hottest zone reading in Celsius, if available.</summary>
    public double? MaxCelsius { get; }

    public static ThermalInfo Unavailable => new(available: false, serious: false, maxCelsius: null);
}

/// <summary>All inputs to a single decision.</summary>
public sealed class DetectionInputs
{
    public bool ManualForceOn { get; init; }
    public bool ManualForceOff { get; init; }
    public bool SessionActive { get; init; }
    public bool ProcessActive { get; init; }

    /// <summary>Executable name driving process activity, for the reason text.</summary>
    public string? ProcessDetail { get; init; }

    public PowerInfo Power { get; init; } = PowerInfo.Desktop;
    public ThermalInfo Thermal { get; init; } = ThermalInfo.Unavailable;
}

/// <summary>The output of a single decision.</summary>
public sealed class DetectionResult
{
    public required bool ShouldStayAwake { get; init; }
    public required ReasonCode Reason { get; init; }

    /// <summary>Battery percent captured for reasons that reference it.</summary>
    public int? BatteryPercent { get; init; }

    /// <summary>Free-form detail (e.g. the process name) for the reason text.</summary>
    public string? Detail { get; init; }
}
