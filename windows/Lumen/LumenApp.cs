using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Lumen.Configuration;
using Lumen.Detection;
using Lumen.Localization;
using Lumen.Power;
using Lumen.Tray;
using Lumen.Ui;

namespace Lumen;

/// <summary>
/// The central coordinator: owns the config/state, the detection components, the
/// power controllers and the tray icon, and drives the poll loop on the UI
/// thread (so <c>SetThreadExecutionState</c> is always called from one thread).
/// </summary>
public sealed class LumenApp : IDisposable
{
    private readonly SessionMonitor _sessions = new();
    private readonly ProcessMonitor _processes = new();
    private readonly ThermalReader _thermal = new();
    private readonly PowerController _power = new();
    private readonly LidPolicyManager _lid = new();

    private AppConfig _config = new();
    private AppState _state = new();
    private TrayIcon? _tray;
    private DispatcherTimer? _timer;
    private SettingsWindow? _settingsWindow;

    private bool _busy;
    private bool _pending;
    private bool _wasAwake;
    private bool _lidBlockedThisCycle;
    private bool _disposed;
    private string? _lastLanguageSetting;

    public void Start()
    {
        _config = ConfigStore.LoadConfig();
        _state = ConfigStore.LoadState();
        Strings.Load(_config.Language);
        _lastLanguageSetting = _config.Language;

        // Crash/exit self-heal: if a previous run left the lid policy overridden,
        // restore it now (one UAC prompt).
        if (_state.LidManaged)
        {
            _lid.Restore(_state);
            ConfigStore.SaveState(_state);
        }

        _tray = new TrayIcon();
        _tray.ModeSelected += OnModeSelected;
        _tray.TimedSelected += OnTimedSelected;
        _tray.SettingsRequested += OpenSettings;
        _tray.ExitRequested += OnExitRequested;

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(_config.PollSeconds) };
        _timer.Tick += (_, _) => PollNow();
        _timer.Start();

        PollNow();
    }

    // --- user actions ---

    private void OnModeSelected(AppMode mode)
    {
        _state.Mode = mode;
        _state.TimedUntilUnix = null; // a manual choice cancels any timed session
        ConfigStore.SaveState(_state);
        PollNow();
    }

    private void OnTimedSelected(TimeSpan duration)
    {
        _state.Mode = AppMode.KeepAwake;
        _state.TimedUntilUnix = DateTimeOffset.UtcNow.Add(duration).ToUnixTimeSeconds();
        ConfigStore.SaveState(_state);
        PollNow();
    }

    private void OpenSettings()
    {
        if (_settingsWindow is not null)
        {
            _settingsWindow.Activate();
            return;
        }

        var window = new SettingsWindow(_config.Clone());
        window.Saved += OnConfigSaved;
        window.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow = window;
        window.Show();
        window.Activate();
    }

    private void OnConfigSaved(AppConfig config)
    {
        ConfigStore.SaveConfig(config);
        PollNow();
    }

    private void OnExitRequested()
    {
        Dispose();
        Application.Current?.Shutdown();
    }

    // --- poll loop ---

    private async void PollNow()
    {
        if (_disposed)
            return;
        if (_busy)
        {
            _pending = true;
            return;
        }

        _busy = true;
        try
        {
            ReloadConfigAndSync();
            AppConfig cfg = _config;
            DetectionResult result = await Task.Run(() => EvaluateOnce(cfg)).ConfigureAwait(true);
            Apply(result, cfg);
        }
        catch
        {
            // Never let a poll error kill the timer.
        }
        finally
        {
            _busy = false;
            if (_pending)
            {
                _pending = false;
                PollNow();
            }
        }
    }

    /// <summary>Re-reads config from disk (single source of truth) and applies
    /// interval/language changes on the UI thread.</summary>
    private void ReloadConfigAndSync()
    {
        _config = ConfigStore.LoadConfig();

        if (_timer is not null)
        {
            var desired = TimeSpan.FromSeconds(_config.PollSeconds);
            if (_timer.Interval != desired)
                _timer.Interval = desired;
        }

        // Language change → reload strings and relabel the menu (only on change).
        if (!string.Equals(_config.Language, _lastLanguageSetting, StringComparison.OrdinalIgnoreCase))
        {
            _lastLanguageSetting = _config.Language;
            Strings.Load(_config.Language);
            _tray?.ApplyLanguage();
        }
    }

    /// <summary>Gathers inputs and evaluates the decision. Runs off the UI thread.</summary>
    private DetectionResult EvaluateOnce(AppConfig cfg)
    {
        DateTimeOffset now = DateTimeOffset.UtcNow;

        // Timed-session expiry reverts to Auto.
        if (_state.TimedUntilUnix is long until && now.ToUnixTimeSeconds() >= until)
        {
            _state.Mode = AppMode.Auto;
            _state.TimedUntilUnix = null;
        }

        bool sessionActive = _sessions.IsSessionActive(cfg);
        bool processActive = _processes.IsProcessActive(cfg);
        PowerInfo power = PowerReader.Read();
        ThermalInfo thermal = _thermal.Read();

        var inputs = new DetectionInputs
        {
            ManualForceOn = _state.Mode is AppMode.KeepAwake or AppMode.Remote,
            ManualForceOff = _state.Mode == AppMode.AllowSleep,
            SessionActive = sessionActive,
            ProcessActive = processActive,
            ProcessDetail = _processes.LastMatch,
            Power = power,
            Thermal = thermal,
        };

        return DetectionEngine.Evaluate(cfg, inputs, _state, now);
    }

    /// <summary>Applies the decision to the OS and UI. Runs on the UI thread.</summary>
    private void Apply(DetectionResult result, AppConfig cfg)
    {
        if (_disposed)
            return;

        bool awake = result.ShouldStayAwake;

        _power.Apply(awake);
        HandleLid(awake, cfg);

        // Clear the "don't re-prompt" latch once we genuinely go idle.
        if (result.Reason is ReasonCode.Idle or ReasonCode.ManualAllowSleep)
            _lidBlockedThisCycle = false;

        _wasAwake = awake;
        ConfigStore.SaveState(_state);

        UpdateTray(result);
    }

    private void HandleLid(bool awake, AppConfig cfg)
    {
        // If the user disabled lid management while it was active, restore now.
        if (!cfg.ManageLidPolicy)
        {
            if (_state.LidManaged)
            {
                _lid.Restore(_state);
                ConfigStore.SaveState(_state);
            }
            return;
        }

        if (awake && !_wasAwake)
        {
            if (!_state.LidManaged && !_lidBlockedThisCycle)
            {
                LidResult r = _lid.ApplyDoNothing(_state);
                ConfigStore.SaveState(_state);
                switch (r)
                {
                    case LidResult.UacDeclined:
                        _lidBlockedThisCycle = true;
                        _tray?.Notify(Strings.Get("notify.lidDeclined.title"), Strings.Get("notify.lidDeclined.body"));
                        break;
                    case LidResult.Failed:
                        _lidBlockedThisCycle = true;
                        _tray?.Notify(Strings.Get("notify.lidFailed.title"), Strings.Get("notify.lidFailed.body"));
                        break;
                }
            }
        }
        else if (!awake && _wasAwake)
        {
            if (_state.LidManaged)
            {
                _lid.Restore(_state);
                ConfigStore.SaveState(_state);
            }
        }
    }

    private void UpdateTray(DetectionResult result)
    {
        IconState iconState =
            _state.Mode == AppMode.AllowSleep ? IconState.Paused :
            result.ShouldStayAwake ? IconState.Awake :
            IconState.Armed;

        string stateLabel = iconState switch
        {
            IconState.Awake => Strings.Get("state.awake"),
            IconState.Paused => Strings.Get("state.paused"),
            _ => Strings.Get("state.armed"),
        };

        string status = $"{stateLabel} — {Strings.Reason(result)}";

        TimeSpan? remaining = null;
        if (_state.TimedUntilUnix is long until)
        {
            long secs = until - DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            if (secs > 0)
                remaining = TimeSpan.FromSeconds(secs);
        }

        _tray?.Update(iconState, _state.Mode, status, remaining);
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;

        _timer?.Stop();
        _timer = null;

        // Crash/exit safety: clear the keep-awake assertion and restore any lid
        // policy we changed.
        try
        {
            _power.Clear();
        }
        catch
        {
            // ignore
        }

        try
        {
            if (_state.LidManaged)
            {
                _lid.Restore(_state);
                ConfigStore.SaveState(_state);
            }
        }
        catch
        {
            // ignore
        }

        _tray?.Dispose();
        _tray = null;
    }
}
