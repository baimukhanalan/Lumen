using System;
using Lumen.Configuration;

namespace Lumen.Detection;

/// <summary>
/// Pure decision logic implementing <c>shared/detection.md</c>. It takes the
/// current config, inputs and (mutable) persisted state, and returns whether the
/// machine should stay awake plus a reason. This is deliberately free of any I/O
/// or OS calls so it matches the macOS logic exactly and is unit-testable.
/// </summary>
public static class DetectionEngine
{
    /// <summary>
    /// Evaluate one poll. May mutate <paramref name="state"/> (OnSince/Capped).
    /// </summary>
    public static DetectionResult Evaluate(AppConfig config, DetectionInputs inputs, AppState state, DateTimeOffset now)
    {
        long nowUnix = now.ToUnixTimeSeconds();

        // 1) Manual "allow sleep" wins over everything and resets the state machine.
        if (inputs.ManualForceOff)
        {
            state.OnSinceUnix = null;
            state.Capped = false;
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.ManualAllowSleep,
            };
        }

        bool activeWork = inputs.SessionActive || inputs.ProcessActive;
        bool anyActive = inputs.ManualForceOn || activeWork;

        // No activity → full reset (self-heal), clears the hard-cap latch.
        if (!anyActive)
        {
            state.OnSinceUnix = null;
            state.Capped = false;
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.Idle,
            };
        }

        // Hard-cap latch: stay asleep-allowed until a genuine idle period clears it.
        if (state.Capped)
        {
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.HardCapWaiting,
            };
        }

        // We want to be awake; stamp the start of this stretch.
        state.OnSinceUnix ??= nowUnix;

        int? battery = inputs.Power.Percent;

        // 2) Safety governors, applied in the order specified by detection.md.
        //    The first that fires wins and forces sleep. These do NOT reset
        //    OnSince/Capped — only a genuine idle period does.

        // (a) Critical battery.
        if (inputs.Power.OnBattery && battery is int critPct && critPct <= config.CriticalBatteryPercent)
        {
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.CriticalBattery,
                BatteryPercent = critPct,
            };
        }

        // (b) Battery floor.
        if (inputs.Power.OnBattery && battery is int floorPct && floorPct <= config.BatteryFloorPercent)
        {
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.BatteryFloor,
                BatteryPercent = floorPct,
            };
        }

        // (c) AC-only mode.
        if (config.AcOnly && inputs.Power.OnBattery)
        {
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.AcOnly,
                BatteryPercent = battery,
            };
        }

        // (d) Thermal release.
        if (inputs.Thermal.Available && inputs.Thermal.Serious)
        {
            return new DetectionResult
            {
                ShouldStayAwake = false,
                Reason = ReasonCode.Thermal,
            };
        }

        // (e) Hard cap on continuous awake time.
        if (config.MaxHours > 0 && state.OnSinceUnix is long onSince)
        {
            long capSeconds = (long)config.MaxHours * 3600L;
            if (nowUnix - onSince >= capSeconds)
            {
                state.Capped = true;
                return new DetectionResult
                {
                    ShouldStayAwake = false,
                    Reason = ReasonCode.HardCap,
                };
            }
        }

        // Otherwise: stay awake.
        ReasonCode reason =
            inputs.ManualForceOn ? ReasonCode.ManualKeepAwake :
            inputs.SessionActive ? ReasonCode.SessionActivity :
            ReasonCode.ProcessActivity;

        return new DetectionResult
        {
            ShouldStayAwake = true,
            Reason = reason,
            BatteryPercent = battery,
            Detail = reason == ReasonCode.ProcessActivity ? inputs.ProcessDetail : null,
        };
    }
}
