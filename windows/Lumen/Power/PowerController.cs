using System;
using System.Runtime.InteropServices;

namespace Lumen.Power;

/// <summary>
/// Applies the keep-awake state via <c>SetThreadExecutionState</c>.
///
/// When keeping awake we set
/// <c>ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED</c>, which holds
/// the system awake even with the lid closed (away-mode keeps work running with
/// the display off). To release we call <c>ES_CONTINUOUS</c> alone.
///
/// The flag is thread-affine, so callers must always invoke this from the same
/// thread (the UI thread, in this app). The OS clears the assertion
/// automatically when the process exits, which is our crash/reboot self-heal.
/// </summary>
public sealed class PowerController
{
    [Flags]
    private enum ExecutionState : uint
    {
        ES_CONTINUOUS = 0x80000000,
        ES_SYSTEM_REQUIRED = 0x00000001,
        ES_DISPLAY_REQUIRED = 0x00000002,
        ES_AWAYMODE_REQUIRED = 0x00000040,
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern ExecutionState SetThreadExecutionState(ExecutionState esFlags);

    private bool _awake;

    /// <summary>Whether keep-awake is currently asserted.</summary>
    public bool IsAwake => _awake;

    /// <summary>
    /// Sets or clears the keep-awake assertion. Idempotent — repeated calls with
    /// the same value re-assert (harmless) so the state survives external clears.
    /// </summary>
    public void Apply(bool stayAwake)
    {
        if (stayAwake)
        {
            SetThreadExecutionState(
                ExecutionState.ES_CONTINUOUS |
                ExecutionState.ES_SYSTEM_REQUIRED |
                ExecutionState.ES_AWAYMODE_REQUIRED);
        }
        else
        {
            SetThreadExecutionState(ExecutionState.ES_CONTINUOUS);
        }

        _awake = stayAwake;
    }

    /// <summary>Clears the assertion (used on exit).</summary>
    public void Clear()
    {
        SetThreadExecutionState(ExecutionState.ES_CONTINUOUS);
        _awake = false;
    }
}
