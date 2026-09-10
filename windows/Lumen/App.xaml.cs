using System;
using System.Threading;
using System.Windows;

namespace Lumen;

/// <summary>
/// WPF application host. Runs with <c>ShutdownMode=OnExplicitShutdown</c> and no
/// main window: the app lives in the tray. The WinForms <c>NotifyIcon</c> is
/// pumped by WPF's dispatcher on this (UI) thread.
/// </summary>
public partial class App : Application
{
    private Mutex? _singleInstance;
    private LumenApp? _controller;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Single-instance guard.
        _singleInstance = new Mutex(initiallyOwned: true, "Lumen.SingleInstance.9F2A7C", out bool createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        // Nicer themed rendering for the WinForms tray menu. Must run before any
        // WinForms control is created; fully-qualified to avoid clashing with
        // System.Windows.Application.
        System.Windows.Forms.Application.EnableVisualStyles();
        System.Windows.Forms.Application.SetCompatibleTextRenderingDefault(false);

        _controller = new LumenApp();
        _controller.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try
        {
            _controller?.Dispose();
        }
        finally
        {
            _singleInstance?.Dispose();
            base.OnExit(e);
        }
    }
}
