using System;
using System.Management;
using Lumen.Detection;

namespace Lumen.Power;

/// <summary>
/// Best-effort thermal reading via WMI (<c>MSAcpi_ThermalZoneTemperature</c>).
/// Many machines do not expose this class (or require admin), so this degrades
/// gracefully: an unavailable reading contributes no thermal governor.
/// </summary>
public sealed class ThermalReader
{
    /// <summary>Hottest zone (°C) at or above which we treat pressure as serious.</summary>
    private const double SeriousThresholdCelsius = 90.0;

    // Once we learn the class is unsupported, stop querying to avoid repeated
    // exceptions every poll.
    private bool _unavailable;

    public ThermalInfo Read()
    {
        if (_unavailable)
            return ThermalInfo.Unavailable;

        try
        {
            double maxCelsius = double.NaN;

            using var searcher = new ManagementObjectSearcher(
                @"root\WMI",
                "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");

            using ManagementObjectCollection results = searcher.Get();
            foreach (ManagementBaseObject obj in results)
            {
                try
                {
                    object? raw = obj["CurrentTemperature"];
                    if (raw is null)
                        continue;

                    // CurrentTemperature is in tenths of a Kelvin.
                    double tenthsKelvin = Convert.ToDouble(raw);
                    double celsius = (tenthsKelvin / 10.0) - 273.15;

                    if (double.IsNaN(maxCelsius) || celsius > maxCelsius)
                        maxCelsius = celsius;
                }
                finally
                {
                    (obj as IDisposable)?.Dispose();
                }
            }

            if (double.IsNaN(maxCelsius))
            {
                // No zones reported — treat as unavailable but keep trying next time.
                return ThermalInfo.Unavailable;
            }

            bool serious = maxCelsius >= SeriousThresholdCelsius;
            return new ThermalInfo(available: true, serious: serious, maxCelsius: maxCelsius);
        }
        catch
        {
            // Not supported on this machine / access denied → give up quietly.
            _unavailable = true;
            return ThermalInfo.Unavailable;
        }
    }
}
