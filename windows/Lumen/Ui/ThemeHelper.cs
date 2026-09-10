using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;

namespace Lumen.Ui;

/// <summary>
/// Applies a light/dark palette to the settings window based on the current
/// Windows "apps" theme. Best-effort: if the theme can't be read, stays light.
/// </summary>
public static class ThemeHelper
{
    public static bool IsSystemDark()
    {
        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            object? value = key?.GetValue("AppsUseLightTheme");
            if (value is int i)
                return i == 0; // 0 = dark, 1 = light
        }
        catch
        {
            // ignore
        }
        return false;
    }

    public static void Apply(Window window)
    {
        if (!IsSystemDark())
            return;

        var bg = new SolidColorBrush(Color.FromRgb(0x20, 0x21, 0x24));
        var fg = new SolidColorBrush(Color.FromRgb(0xEC, 0xED, 0xEF));
        var inputBg = new SolidColorBrush(Color.FromRgb(0x2C, 0x2E, 0x33));

        window.Background = bg;
        window.Foreground = fg;

        var textBoxStyle = new Style(typeof(TextBox));
        textBoxStyle.Setters.Add(new Setter(Control.BackgroundProperty, inputBg));
        textBoxStyle.Setters.Add(new Setter(Control.ForegroundProperty, fg));
        textBoxStyle.Setters.Add(new Setter(Control.BorderBrushProperty,
            new SolidColorBrush(Color.FromRgb(0x45, 0x47, 0x4D))));
        window.Resources[typeof(TextBox)] = textBoxStyle;

        var comboStyle = new Style(typeof(ComboBox));
        comboStyle.Setters.Add(new Setter(Control.BackgroundProperty, inputBg));
        comboStyle.Setters.Add(new Setter(Control.ForegroundProperty, fg));
        window.Resources[typeof(ComboBox)] = comboStyle;
    }
}
