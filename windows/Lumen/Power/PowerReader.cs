using System;
using System.Windows.Forms;
using Lumen.Detection;

namespace Lumen.Power;

/// <summary>
/// Reads battery / AC state via <see cref="SystemInformation.PowerStatus"/>.
/// This is the simplest reliable source on Windows and needs no WMI.
/// </summary>
public static class PowerReader
{
    public static PowerInfo Read()
    {
        try
        {
            PowerStatus status = SystemInformation.PowerStatus;

            bool noBattery = (status.BatteryChargeStatus & BatteryChargeStatus.NoSystemBattery) != 0;
            if (noBattery)
                return PowerInfo.Desktop;

            bool onBattery = status.PowerLineStatus == PowerLineStatus.Offline;

            int? percent = null;
            float life = status.BatteryLifePercent; // 0.0..1.0, or 255/large when unknown
            if (life >= 0f && life <= 1f)
                percent = (int)Math.Round(life * 100f);

            return new PowerInfo(hasBattery: true, onBattery: onBattery, percent: percent);
        }
        catch
        {
            // If anything goes wrong, assume desktop/AC so we never wrongly force sleep.
            return PowerInfo.Desktop;
        }
    }
}
