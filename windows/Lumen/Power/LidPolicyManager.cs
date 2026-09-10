using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Lumen.Configuration;

namespace Lumen.Power;

/// <summary>Outcome of a lid-policy change.</summary>
public enum LidResult
{
    /// <summary>The change was applied (or nothing needed doing).</summary>
    Success,

    /// <summary>The user dismissed the UAC prompt.</summary>
    UacDeclined,

    /// <summary>powercfg was unavailable or failed.</summary>
    Failed,
}

/// <summary>
/// Manages the Windows lid-close power policy via <c>powercfg</c>.
///
/// Reading the current value is done non-elevated. Changing it requires
/// elevation, so the set/restore commands are bundled into a single
/// <c>cmd.exe</c> invocation launched with the <c>runas</c> verb — exactly one
/// UAC prompt per enable and per restore. The app itself stays non-elevated.
///
/// Previous values are stored in <see cref="AppState"/> so the policy can be
/// restored even after a crash (checked on next startup).
/// </summary>
public sealed class LidPolicyManager
{
    // powercfg aliases: SUB_BUTTONS is the "Power buttons and lid" subgroup and
    // LIDACTION is the "Lid close action" setting. 0 = Do nothing.
    private const string SubButtons = "SUB_BUTTONS";
    private const string LidAction = "LIDACTION";
    private const int DoNothing = 0;
    private const int DefaultSleep = 1; // fallback if a previous value is unknown

    /// <summary>
    /// Sets the lid-close action to "Do nothing" for both AC and DC, storing the
    /// previous values in <paramref name="state"/>. No-op if already managed.
    /// </summary>
    public LidResult ApplyDoNothing(AppState state)
    {
        if (state.LidManaged)
            return LidResult.Success;

        if (!TryReadCurrent(out int ac, out int dc))
            return LidResult.Failed;

        string command =
            $"powercfg /setacvalueindex SCHEME_CURRENT {SubButtons} {LidAction} {DoNothing} & " +
            $"powercfg /setdcvalueindex SCHEME_CURRENT {SubButtons} {LidAction} {DoNothing} & " +
            "powercfg /setactive SCHEME_CURRENT";

        LidResult result = RunElevated(command);
        if (result == LidResult.Success)
        {
            state.SavedLidAc = ac;
            state.SavedLidDc = dc;
            state.LidManaged = true;
        }

        return result;
    }

    /// <summary>
    /// Restores the previously saved lid-close action. No-op if not managed.
    /// On success, clears the managed flag in <paramref name="state"/>.
    /// </summary>
    public LidResult Restore(AppState state)
    {
        if (!state.LidManaged)
            return LidResult.Success;

        int ac = state.SavedLidAc ?? DefaultSleep;
        int dc = state.SavedLidDc ?? DefaultSleep;

        string command =
            $"powercfg /setacvalueindex SCHEME_CURRENT {SubButtons} {LidAction} {ac} & " +
            $"powercfg /setdcvalueindex SCHEME_CURRENT {SubButtons} {LidAction} {dc} & " +
            "powercfg /setactive SCHEME_CURRENT";

        LidResult result = RunElevated(command);
        if (result == LidResult.Success)
        {
            state.LidManaged = false;
            state.SavedLidAc = null;
            state.SavedLidDc = null;
        }

        return result;
    }

    // --- helpers ---

    private static readonly Regex AcRegex =
        new(@"Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)", RegexOptions.Compiled);
    private static readonly Regex DcRegex =
        new(@"Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)", RegexOptions.Compiled);

    /// <summary>Reads the current AC/DC lid-action indices (non-elevated).</summary>
    private static bool TryReadCurrent(out int ac, out int dc)
    {
        ac = DefaultSleep;
        dc = DefaultSleep;

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "powercfg.exe",
                Arguments = $"/query SCHEME_CURRENT {SubButtons} {LidAction}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
                StandardOutputEncoding = Encoding.UTF8,
            };

            using Process? proc = Process.Start(psi);
            if (proc is null)
                return false;

            string output = proc.StandardOutput.ReadToEnd();
            proc.WaitForExit(5000);

            Match acMatch = AcRegex.Match(output);
            Match dcMatch = DcRegex.Match(output);
            if (!acMatch.Success || !dcMatch.Success)
                return false;

            ac = int.Parse(acMatch.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            dc = int.Parse(dcMatch.Groups[1].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Runs a command string via an elevated hidden <c>cmd.exe</c>.</summary>
    private static LidResult RunElevated(string command)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c " + command,
                Verb = "runas",            // triggers the single UAC prompt
                UseShellExecute = true,     // required for the runas verb
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
            };

            using Process? proc = Process.Start(psi);
            if (proc is null)
                return LidResult.Failed;

            proc.WaitForExit(15000);
            return proc.HasExited && proc.ExitCode == 0 ? LidResult.Success : LidResult.Failed;
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            // ERROR_CANCELLED — the user declined the UAC prompt.
            return LidResult.UacDeclined;
        }
        catch
        {
            return LidResult.Failed;
        }
    }
}
