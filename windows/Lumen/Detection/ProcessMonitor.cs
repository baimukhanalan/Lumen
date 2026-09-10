using System;
using System.Collections.Generic;
using System.Diagnostics;
using Lumen.Configuration;

namespace Lumen.Detection;

/// <summary>
/// Optional process + CPU trigger. Matches configured executable names and
/// requires sustained CPU ≥ <c>cpuThresholdPercent</c> to count as "working".
///
/// CPU usage is computed from the delta of <see cref="Process.TotalProcessorTime"/>
/// between polls (pure BCL, no PerformanceCounter dependency), normalized by wall
/// time and processor count.
/// </summary>
public sealed class ProcessMonitor
{
    private sealed record Sample(TimeSpan Cpu, DateTime WallUtc);

    // Keyed by process id → last CPU sample, so each poll measures over the
    // interval since the previous poll.
    private readonly Dictionary<int, Sample> _samples = new();
    private readonly int _processorCount = Math.Max(1, Environment.ProcessorCount);

    public string? LastMatch { get; private set; }

    /// <summary>
    /// Returns true if any watched process sustained CPU at or above the
    /// configured threshold since the previous poll.
    /// </summary>
    public bool IsProcessActive(AppConfig config)
    {
        LastMatch = null;

        if (!config.EnableProcessTriggers || config.ProcessList.Count == 0)
        {
            _samples.Clear();
            return false;
        }

        var seen = new HashSet<int>();
        DateTime nowUtc = DateTime.UtcNow;
        bool active = false;

        foreach (string rawName in config.ProcessList)
        {
            string name = NormalizeName(rawName);
            if (name.Length == 0)
                continue;

            Process[] procs;
            try
            {
                procs = Process.GetProcessesByName(name);
            }
            catch
            {
                continue;
            }

            foreach (Process proc in procs)
            {
                try
                {
                    int pid = proc.Id;
                    seen.Add(pid);

                    TimeSpan cpu = proc.TotalProcessorTime;

                    if (_samples.TryGetValue(pid, out Sample? prev))
                    {
                        double wallMs = (nowUtc - prev.WallUtc).TotalMilliseconds;
                        if (wallMs > 0)
                        {
                            double cpuMs = (cpu - prev.Cpu).TotalMilliseconds;
                            double percent = cpuMs / (wallMs * _processorCount) * 100.0;
                            if (percent >= config.CpuThresholdPercent)
                            {
                                active = true;
                                LastMatch = name;
                            }
                        }
                    }

                    _samples[pid] = new Sample(cpu, nowUtc);
                }
                catch
                {
                    // Access denied / process exited; skip it.
                }
                finally
                {
                    proc.Dispose();
                }
            }
        }

        // Drop samples for processes that no longer exist.
        if (_samples.Count > 0)
        {
            var stale = new List<int>();
            foreach (int pid in _samples.Keys)
            {
                if (!seen.Contains(pid))
                    stale.Add(pid);
            }
            foreach (int pid in stale)
                _samples.Remove(pid);
        }

        return active;
    }

    private static string NormalizeName(string raw)
    {
        string name = raw.Trim();
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            name = name[..^4];
        return name;
    }
}
