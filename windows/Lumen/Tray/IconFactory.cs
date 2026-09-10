using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace Lumen.Tray;

/// <summary>
/// Generates simple tray icons in code (no binary assets) so the repository
/// stays text-only and the build is self-contained. Each icon is drawn on a
/// transparent 32×32 canvas and converted to a Win32 icon.
///
/// The caller owns the returned <see cref="GeneratedIcon"/> and must dispose it
/// (which also frees the underlying HICON via <c>DestroyIcon</c>).
/// </summary>
public static class IconFactory
{
    private const int Size = 32;

    private static readonly Color Awake = Color.FromArgb(245, 179, 1);   // warm gold
    private static readonly Color Armed = Color.FromArgb(59, 158, 255);  // blue
    private static readonly Color Paused = Color.FromArgb(138, 143, 152); // gray

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);

    /// <summary>An icon plus the native handle that must be destroyed.</summary>
    public sealed class GeneratedIcon : IDisposable
    {
        private IntPtr _handle;
        public Icon Icon { get; }

        internal GeneratedIcon(Icon icon, IntPtr handle)
        {
            Icon = icon;
            _handle = handle;
        }

        public void Dispose()
        {
            Icon.Dispose();
            if (_handle != IntPtr.Zero)
            {
                DestroyIcon(_handle);
                _handle = IntPtr.Zero;
            }
        }
    }

    public static GeneratedIcon Create(IconState state)
    {
        using var bmp = new Bitmap(Size, Size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);

            switch (state)
            {
                case IconState.Awake:
                    DrawSun(g);
                    break;
                case IconState.Armed:
                    DrawRing(g);
                    break;
                case IconState.Paused:
                    DrawMoon(g);
                    break;
            }
        }

        IntPtr handle = bmp.GetHicon();
        Icon icon = (Icon)Icon.FromHandle(handle).Clone();
        return new GeneratedIcon(icon, handle);
    }

    /// <summary>Awake: a filled sun with rays.</summary>
    private static void DrawSun(Graphics g)
    {
        const float cx = Size / 2f, cy = Size / 2f;
        float coreR = 7f;

        using var pen = new Pen(Awake, 2.4f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        for (int i = 0; i < 8; i++)
        {
            double a = i * Math.PI / 4.0;
            float inner = coreR + 3f;
            float outer = coreR + 7f;
            var p1 = new PointF(cx + (float)Math.Cos(a) * inner, cy + (float)Math.Sin(a) * inner);
            var p2 = new PointF(cx + (float)Math.Cos(a) * outer, cy + (float)Math.Sin(a) * outer);
            g.DrawLine(pen, p1, p2);
        }

        using var brush = new SolidBrush(Awake);
        g.FillEllipse(brush, cx - coreR, cy - coreR, coreR * 2, coreR * 2);
    }

    /// <summary>Armed: a hollow ring (watching, currently allowing sleep).</summary>
    private static void DrawRing(Graphics g)
    {
        const float cx = Size / 2f, cy = Size / 2f;
        float r = 10f;
        using var pen = new Pen(Armed, 3f);
        g.DrawEllipse(pen, cx - r, cy - r, r * 2, r * 2);
        using var brush = new SolidBrush(Armed);
        g.FillEllipse(brush, cx - 2.5f, cy - 2.5f, 5f, 5f);
    }

    /// <summary>Paused: a crescent moon (sleep allowed).</summary>
    private static void DrawMoon(Graphics g)
    {
        const float cx = Size / 2f, cy = Size / 2f;
        float r = 11f;

        using var brush = new SolidBrush(Paused);
        g.FillEllipse(brush, cx - r, cy - r, r * 2, r * 2);

        // Carve out an offset circle to leave a crescent. SourceCopy replaces
        // pixels (including alpha) so the cut-out becomes transparent.
        CompositingMode prev = g.CompositingMode;
        g.CompositingMode = CompositingMode.SourceCopy;
        using (var cut = new SolidBrush(Color.Transparent))
        {
            float offset = 6.5f;
            g.FillEllipse(cut, cx - r + offset, cy - r - 2f, r * 2, r * 2);
        }
        g.CompositingMode = prev;
    }
}
