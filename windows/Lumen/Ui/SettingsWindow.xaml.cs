using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using Lumen.Configuration;
using Lumen.Localization;

namespace Lumen.Ui;

/// <summary>
/// The settings window (General / Triggers / Safety / About), editing a working
/// copy of <see cref="AppConfig"/>. Raises <see cref="Saved"/> with the new
/// config when the user saves.
/// </summary>
public partial class SettingsWindow : Window
{
    private readonly AppConfig _config;

    /// <summary>Raised with the edited config when the user clicks Save.</summary>
    public event Action<AppConfig>? Saved;

    public SettingsWindow(AppConfig config)
    {
        _config = config;
        InitializeComponent();

        ThemeHelper.Apply(this);
        BuildLanguageItems();
        Localize();
        LoadValues();

        BtnSave.Click += (_, _) => Save();
        BtnClose.Click += (_, _) => Close();
    }

    private void BuildLanguageItems()
    {
        CmbLanguage.Items.Clear();
        CmbLanguage.Items.Add(new ComboBoxItem { Content = Strings.Get("settings.general.language.auto"), Tag = "" });
        CmbLanguage.Items.Add(new ComboBoxItem { Content = "English", Tag = "en" });
        CmbLanguage.Items.Add(new ComboBoxItem { Content = "Русский", Tag = "ru" });
        CmbLanguage.Items.Add(new ComboBoxItem { Content = "Қазақша", Tag = "kk" });
    }

    private void Localize()
    {
        Title = Strings.Get("settings.title");

        TabGeneral.Header = Strings.Get("settings.tab.general");
        TabTriggers.Header = Strings.Get("settings.tab.triggers");
        TabSafety.Header = Strings.Get("settings.tab.safety");
        TabAbout.Header = Strings.Get("settings.tab.about");

        LblPoll.Text = Strings.Get("settings.general.pollSeconds");
        LblGrace.Text = Strings.Get("settings.general.graceMinutes");
        ChkWatchClaude.Content = Strings.Get("settings.general.watchClaude");
        ChkWatchCodex.Content = Strings.Get("settings.general.watchCodex");
        LblLanguage.Text = Strings.Get("settings.general.language");
        ChkManageLid.Content = Strings.Get("settings.general.manageLid");
        LblLidHint.Text = Strings.Get("settings.general.manageLid.hint");

        ChkEnableProc.Content = Strings.Get("settings.triggers.enable");
        LblCpu.Text = Strings.Get("settings.triggers.cpuThreshold");
        LblProcList.Text = Strings.Get("settings.triggers.processList");
        LblProcHint.Text = Strings.Get("settings.triggers.processList.hint");

        LblBatFloor.Text = Strings.Get("settings.safety.batteryFloor");
        LblCrit.Text = Strings.Get("settings.safety.criticalBattery");
        LblMaxHours.Text = Strings.Get("settings.safety.maxHours");
        ChkAcOnly.Content = Strings.Get("settings.safety.acOnly");
        LblSafetyHint.Text = Strings.Get("settings.safety.hint");

        LblAppName.Text = Strings.Get("app.name");
        LblTagline.Text = Strings.Get("app.tagline");
        LblVersion.Text = Strings.Format("settings.about.version", AppVersion());
        LblDescription.Text = Strings.Get("settings.about.description");
        LblConfigLabel.Text = Strings.Get("settings.about.config");
        TxtConfigPath.Text = ConfigStore.ConfigPath;
        LblLinks.Text = Strings.Get("settings.about.links");

        BtnSave.Content = Strings.Get("settings.save");
        BtnClose.Content = Strings.Get("settings.close");
    }

    private void LoadValues()
    {
        TxtPoll.Text = _config.PollSeconds.ToString(CultureInfo.InvariantCulture);
        TxtGrace.Text = _config.GraceMinutes.ToString(CultureInfo.InvariantCulture);
        ChkWatchClaude.IsChecked = _config.WatchClaude;
        ChkWatchCodex.IsChecked = _config.WatchCodex;

        ChkManageLid.IsChecked = _config.ManageLidPolicy;

        ChkEnableProc.IsChecked = _config.EnableProcessTriggers;
        TxtCpu.Text = _config.CpuThresholdPercent.ToString(CultureInfo.InvariantCulture);
        TxtProcList.Text = string.Join(Environment.NewLine, _config.ProcessList);

        TxtBatFloor.Text = _config.BatteryFloorPercent.ToString(CultureInfo.InvariantCulture);
        TxtCrit.Text = _config.CriticalBatteryPercent.ToString(CultureInfo.InvariantCulture);
        TxtMaxHours.Text = _config.MaxHours.ToString(CultureInfo.InvariantCulture);
        ChkAcOnly.IsChecked = _config.AcOnly;

        string current = _config.Language ?? "";
        foreach (ComboBoxItem item in CmbLanguage.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals((string)(item.Tag ?? ""), current, StringComparison.OrdinalIgnoreCase))
            {
                CmbLanguage.SelectedItem = item;
                break;
            }
        }
        if (CmbLanguage.SelectedItem is null && CmbLanguage.Items.Count > 0)
            CmbLanguage.SelectedIndex = 0;
    }

    private void Save()
    {
        var cfg = _config.Clone();

        cfg.PollSeconds = ParseInt(TxtPoll.Text, cfg.PollSeconds);
        cfg.GraceMinutes = ParseInt(TxtGrace.Text, cfg.GraceMinutes);
        cfg.WatchClaude = ChkWatchClaude.IsChecked == true;
        cfg.WatchCodex = ChkWatchCodex.IsChecked == true;
        cfg.ManageLidPolicy = ChkManageLid.IsChecked == true;

        cfg.EnableProcessTriggers = ChkEnableProc.IsChecked == true;
        cfg.CpuThresholdPercent = ParseInt(TxtCpu.Text, cfg.CpuThresholdPercent);
        cfg.ProcessList = ParseList(TxtProcList.Text);

        cfg.BatteryFloorPercent = ParseInt(TxtBatFloor.Text, cfg.BatteryFloorPercent);
        cfg.CriticalBatteryPercent = ParseInt(TxtCrit.Text, cfg.CriticalBatteryPercent);
        cfg.MaxHours = ParseInt(TxtMaxHours.Text, cfg.MaxHours);
        cfg.AcOnly = ChkAcOnly.IsChecked == true;

        string tag = (CmbLanguage.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
        cfg.Language = string.IsNullOrEmpty(tag) ? null : tag;

        cfg.Normalize();

        Saved?.Invoke(cfg);
        Close();
    }

    private static int ParseInt(string text, int fallback)
        => int.TryParse(text?.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int v) ? v : fallback;

    private static List<string> ParseList(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return new List<string>();

        return text
            .Split(new[] { '\r', '\n', ',' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.Trim())
            .Where(s => s.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static string AppVersion()
    {
        Version? v = Assembly.GetExecutingAssembly().GetName().Version;
        return v is null ? "0.1.0" : $"{v.Major}.{v.Minor}.{v.Build}";
    }
}
