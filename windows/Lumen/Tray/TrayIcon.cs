using System;
using System.Collections.Generic;
using System.Windows.Forms;
using Lumen.Configuration;
using Lumen.Localization;

namespace Lumen.Tray;

/// <summary>
/// The system-tray presence: a <see cref="NotifyIcon"/> with a context menu
/// mirroring the macOS app (live status line, modes, timed sessions, settings,
/// exit). Raises events for user actions; it holds no application logic.
/// </summary>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;

    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripMenuItem _modeHeader;
    private readonly ToolStripMenuItem _autoItem;
    private readonly ToolStripMenuItem _keepAwakeItem;
    private readonly ToolStripMenuItem _allowSleepItem;
    private readonly ToolStripMenuItem _remoteItem;
    private readonly ToolStripMenuItem _timedHeader;
    private readonly ToolStripMenuItem _settingsItem;
    private readonly ToolStripMenuItem _exitItem;
    private readonly List<ToolStripMenuItem> _timedItems = new();

    private readonly Dictionary<IconState, IconFactory.GeneratedIcon> _icons = new();
    private IconState _currentState = IconState.Armed;

    public event Action<AppMode>? ModeSelected;
    public event Action<TimeSpan>? TimedSelected;
    public event Action? SettingsRequested;
    public event Action? ExitRequested;

    private static readonly (string key, int minutes)[] TimedOptions =
    {
        ("menu.timed.15m", 15),
        ("menu.timed.30m", 30),
        ("menu.timed.1h", 60),
        ("menu.timed.2h", 120),
        ("menu.timed.4h", 240),
        ("menu.timed.8h", 480),
    };

    public TrayIcon()
    {
        foreach (IconState state in Enum.GetValues<IconState>())
            _icons[state] = IconFactory.Create(state);

        _statusItem = new ToolStripMenuItem { Enabled = false };
        _modeHeader = new ToolStripMenuItem();

        _autoItem = MakeModeItem(AppMode.Auto);
        _keepAwakeItem = MakeModeItem(AppMode.KeepAwake);
        _allowSleepItem = MakeModeItem(AppMode.AllowSleep);
        _remoteItem = MakeModeItem(AppMode.Remote);
        _modeHeader.DropDownItems.AddRange(new ToolStripItem[]
        {
            _autoItem, _keepAwakeItem, _allowSleepItem, _remoteItem,
        });

        _timedHeader = new ToolStripMenuItem();
        foreach (var (key, minutes) in TimedOptions)
        {
            var item = new ToolStripMenuItem { Tag = TimeSpan.FromMinutes(minutes) };
            item.Click += (_, _) =>
            {
                if (item.Tag is TimeSpan ts)
                    TimedSelected?.Invoke(ts);
            };
            _timedItems.Add(item);
            _timedHeader.DropDownItems.Add(item);
        }

        _settingsItem = new ToolStripMenuItem();
        _settingsItem.Click += (_, _) => SettingsRequested?.Invoke();

        _exitItem = new ToolStripMenuItem();
        _exitItem.Click += (_, _) => ExitRequested?.Invoke();

        _menu = new ContextMenuStrip();
        _menu.Items.AddRange(new ToolStripItem[]
        {
            _statusItem,
            new ToolStripSeparator(),
            _modeHeader,
            _timedHeader,
            new ToolStripSeparator(),
            _settingsItem,
            _exitItem,
        });

        _notifyIcon = new NotifyIcon
        {
            Visible = true,
            Icon = _icons[_currentState].Icon,
            ContextMenuStrip = _menu,
        };
        _notifyIcon.DoubleClick += (_, _) => SettingsRequested?.Invoke();

        ApplyLanguage();
    }

    private ToolStripMenuItem MakeModeItem(AppMode mode)
    {
        var item = new ToolStripMenuItem { Tag = mode };
        item.Click += (_, _) => ModeSelected?.Invoke(mode);
        return item;
    }

    /// <summary>Re-applies localized labels (call after a language change).</summary>
    public void ApplyLanguage()
    {
        _modeHeader.Text = Strings.Get("menu.mode");
        _autoItem.Text = Strings.Get("menu.mode.auto");
        _keepAwakeItem.Text = Strings.Get("menu.mode.keepAwake");
        _allowSleepItem.Text = Strings.Get("menu.mode.allowSleep");
        _remoteItem.Text = Strings.Get("menu.mode.remote");
        _timedHeader.Text = Strings.Get("menu.timed");
        for (int i = 0; i < _timedItems.Count; i++)
            _timedItems[i].Text = Strings.Get(TimedOptions[i].key);
        _settingsItem.Text = Strings.Get("menu.settings");
        _exitItem.Text = Strings.Get("menu.exit");
    }

    /// <summary>Updates the icon, status line, mode checkmarks and tooltip.</summary>
    public void Update(IconState state, AppMode mode, string statusText, TimeSpan? timedRemaining)
    {
        if (state != _currentState)
        {
            _currentState = state;
            _notifyIcon.Icon = _icons[state].Icon;
        }

        _statusItem.Text = statusText;

        _autoItem.Checked = mode == AppMode.Auto;
        _keepAwakeItem.Checked = mode == AppMode.KeepAwake;
        _allowSleepItem.Checked = mode == AppMode.AllowSleep;
        _remoteItem.Checked = mode == AppMode.Remote;

        // Reflect an active timed session on the submenu header.
        _timedHeader.Text = timedRemaining is TimeSpan remaining && remaining > TimeSpan.Zero
            ? $"{Strings.Get("menu.timed")} — {Strings.Format("menu.timed.remaining", FormatSpan(remaining))}"
            : Strings.Get("menu.timed");

        // Tooltip is limited to 63 characters.
        _notifyIcon.Text = Truncate(statusText, 63);
    }

    /// <summary>Shows a balloon notification.</summary>
    public void Notify(string title, string body)
    {
        _notifyIcon.BalloonTipTitle = Truncate(title, 63);
        _notifyIcon.BalloonTipText = Truncate(body, 255);
        _notifyIcon.ShowBalloonTip(6000);
    }

    private static string FormatSpan(TimeSpan span)
    {
        if (span.TotalHours >= 1)
            return $"{(int)span.TotalHours}h {span.Minutes}m";
        if (span.TotalMinutes >= 1)
            return $"{span.Minutes}m";
        return $"{span.Seconds}s";
    }

    private static string Truncate(string value, int max)
        => value.Length <= max ? value : value[..(max - 1)] + "…";

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
        foreach (var icon in _icons.Values)
            icon.Dispose();
        _icons.Clear();
    }
}
