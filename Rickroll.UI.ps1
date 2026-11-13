#Requires -Version 5.1
<#
    Rickroll.UI - the custom-drawn controls used by Launcher.ps1.
    Dot-sourced by the launcher; the C# is compiled once per process.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RickrollDpi
{
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@

[void][RickrollDpi]::SetProcessDPIAware()

if (-not ('Rickroll.UI.RoundButton' -as [type])) {
    $references = @(
        [System.Windows.Forms.Form].Assembly.Location,
        [System.Drawing.Point].Assembly.Location
    )

    Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace Rickroll.UI
{
    public static class Shapes
    {
        public static GraphicsPath Rounded(Rectangle rect, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            // Winding, not the default Alternate: when the radius is close to half the
            // size the arcs overlap, and Alternate punches wedge-shaped holes in the
            // corners that show whatever happened to be painted there before.
            path.FillMode = FillMode.Winding;
            int d = Math.Min(radius * 2, Math.Min(rect.Width, rect.Height));
            if (d <= 0) { path.AddRectangle(rect); return path; }
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        public static Color CornerOf(Control control)
        {
            Control parent = control.Parent;
            if (parent == null) { return Color.FromArgb(14, 15, 21); }
            RoundPanel panel = parent as RoundPanel;
            if (panel != null) { return panel.FillColor; }
            Color back = parent.BackColor;
            return back.A == 0 ? Color.FromArgb(14, 15, 21) : back;
        }
    }

    public class RoundPanel : Panel
    {
        public int Radius { get; set; }
        public Color FillColor { get; set; }
        public Color BorderColor { get; set; }
        public Color CornerColor { get; set; }

        public RoundPanel()
        {
            Radius = 14;
            FillColor = Color.FromArgb(22, 24, 36);
            BorderColor = Color.FromArgb(39, 42, 60);
            CornerColor = Color.Empty;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Color.FromArgb(14, 15, 21);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
            Color corner = CornerColor.IsEmpty ? Shapes.CornerOf(this) : CornerColor;
            using (SolidBrush backing = new SolidBrush(corner)) { e.Graphics.FillRectangle(backing, ClientRectangle); }
            using (GraphicsPath path = Shapes.Rounded(rect, Radius))
            using (SolidBrush brush = new SolidBrush(FillColor))
            {
                e.Graphics.FillPath(brush, path);
                if (BorderColor.A > 0)
                {
                    using (Pen pen = new Pen(BorderColor)) { e.Graphics.DrawPath(pen, path); }
                }
            }
            base.OnPaint(e);
        }
    }

    public class RoundButton : Button
    {
        public int Radius { get; set; }
        public Color FillColor { get; set; }
        public Color HoverFill { get; set; }
        public Color PressFill { get; set; }
        public Color BorderColor { get; set; }
        public Color CornerColor { get; set; }
        private bool hovered;
        private bool pressed;

        public RoundButton()
        {
            Radius = 12;
            FillColor = Color.FromArgb(27, 30, 44);
            HoverFill = Color.FromArgb(42, 46, 68);
            PressFill = Color.FromArgb(34, 38, 58);
            BorderColor = Color.Transparent;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            BackColor = Color.Transparent;
            ForeColor = Color.FromArgb(232, 233, 240);
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { pressed = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            Color fill = Enabled ? (pressed ? PressFill : (hovered ? HoverFill : FillColor)) : Color.FromArgb(28, 30, 42);
            Color text = Enabled ? ForeColor : Color.FromArgb(104, 108, 126);
            Color border = Enabled ? BorderColor : Color.FromArgb(38, 41, 58);
            Color corner = CornerColor.IsEmpty ? Shapes.CornerOf(this) : CornerColor;
            using (SolidBrush backing = new SolidBrush(corner)) { g.FillRectangle(backing, ClientRectangle); }

            Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = Shapes.Rounded(rect, Radius))
            using (SolidBrush brush = new SolidBrush(fill))
            {
                g.FillPath(brush, path);
                if (border.A > 0)
                {
                    using (Pen pen = new Pen(border)) { g.DrawPath(pen, path); }
                }
            }

            using (StringFormat format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            using (SolidBrush brush = new SolidBrush(text))
            {
                g.DrawString(Text, Font, brush, new RectangleF(0, 0, Width, Height), format);
            }
        }
    }

    public class CaptionButton : Control
    {
        public string Glyph { get; set; }
        public Color HoverFill { get; set; }
        public Color GlyphColor { get; set; }
        public Color HoverGlyphColor { get; set; }
        public Color CornerColor { get; set; }
        private bool hovered;
        private bool pressed;

        public CaptionButton()
        {
            CornerColor = Color.Empty;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            Glyph = "min";
            HoverFill = Color.FromArgb(35, 39, 57);
            GlyphColor = Color.FromArgb(150, 156, 176);
            HoverGlyphColor = Color.White;
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        public void SetGlyph(string glyph) { Glyph = glyph; Invalidate(); }

        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { pressed = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Color corner = CornerColor.IsEmpty ? Shapes.CornerOf(this) : CornerColor;
            using (SolidBrush backing = new SolidBrush(corner)) { g.FillRectangle(backing, ClientRectangle); }

            if (hovered || pressed)
            {
                Color fill = pressed ? ControlPaint.Dark(HoverFill, 0.15f) : HoverFill;
                using (GraphicsPath path = Shapes.Rounded(new Rectangle(0, 0, Width - 1, Height - 1), 7))
                using (SolidBrush brush = new SolidBrush(fill)) { g.FillPath(brush, path); }
            }

            using (Pen pen = new Pen(hovered ? HoverGlyphColor : GlyphColor, 1.2f))
            {
                int cx = Width / 2;
                int cy = Height / 2;
                switch (Glyph)
                {
                    case "min":
                        g.DrawLine(pen, cx - 5, cy, cx + 5, cy);
                        break;
                    case "max":
                        g.DrawRectangle(pen, cx - 5, cy - 5, 10, 10);
                        break;
                    case "restore":
                        g.DrawRectangle(pen, cx - 5, cy - 3, 8, 8);
                        g.DrawLine(pen, cx - 3, cy - 5, cx + 5, cy - 5);
                        g.DrawLine(pen, cx + 5, cy - 5, cx + 5, cy + 3);
                        break;
                    case "close":
                        g.DrawLine(pen, cx - 5, cy - 5, cx + 5, cy + 5);
                        g.DrawLine(pen, cx + 5, cy - 5, cx - 5, cy + 5);
                        break;
                }
            }
        }
    }

    public class HotkeyWindow : NativeWindow, IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const int IdBase = 0xA000;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public event EventHandler HotkeyPressed;

        public HotkeyWindow() { CreateHandle(new CreateParams()); }

        public bool Register(int slot, uint modifiers, uint vk)
        {
            return RegisterHotKey(Handle, IdBase + slot, modifiers, vk);
        }

        public void Unregister(int slot)
        {
            try { UnregisterHotKey(Handle, IdBase + slot); } catch { }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY)
            {
                EventHandler handler = HotkeyPressed;
                if (handler != null) { handler(this, EventArgs.Empty); }
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (Handle != IntPtr.Zero) { DestroyHandle(); }
        }
    }

    public class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public Color MenuBack { get; set; }
        public Color HoverBack { get; set; }
        public Color ItemText { get; set; }
        public Color LineColor { get; set; }
        public Color DimText { get; set; }

        public DarkMenuRenderer()
        {
            MenuBack = Color.FromArgb(24, 26, 38);
            HoverBack = Color.FromArgb(38, 41, 62);
            ItemText = Color.FromArgb(230, 231, 238);
            LineColor = Color.FromArgb(44, 47, 66);
            DimText = Color.FromArgb(138, 143, 166);
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using (SolidBrush brush = new SolidBrush(MenuBack)) { e.Graphics.FillRectangle(brush, e.AffectedBounds); }
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            using (Pen pen = new Pen(LineColor)) { e.Graphics.DrawRectangle(pen, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1); }
        }

        protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (!e.Item.Selected) { return; }
            Rectangle rect = new Rectangle(4, 1, e.Item.Width - 8, e.Item.Height - 2);
            using (GraphicsPath path = Shapes.Rounded(rect, 6))
            using (SolidBrush brush = new SolidBrush(HoverBack)) { e.Graphics.FillPath(brush, path); }
        }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.Enabled ? ItemText : DimText;
            base.OnRenderItemText(e);
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            using (Pen pen = new Pen(LineColor))
            {
                int y = e.Item.Height / 2;
                e.Graphics.DrawLine(pen, 10, y, e.Item.Width - 10, y);
            }
        }

        protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) { }
    }

    /// <summary>
    /// Frame-driven tween for a single int property, eased out with a small
    /// overshoot. Lives in C# because a PowerShell-driven loop can only manage
    /// a couple of frames before the animation is over.
    /// </summary>
    public class Animator
    {
        private static readonly System.Reflection.PropertyInfo WidthProperty = typeof(Control).GetProperty("Width");
        private static readonly System.Reflection.PropertyInfo TopProperty = typeof(Control).GetProperty("Top");

        private readonly Control target;
        private readonly bool vertical;
        private readonly Timer timer;
        private double from;
        private double to;
        private double startedMs;
        private double durationMs;

        public Action Completed { get; set; }

        public Animator(Control target, string property)
        {
            this.target = target;
            vertical = property == "Top";
            timer = new Timer();
            timer.Interval = 12;
            timer.Tick += delegate { Step(); };
        }

        public bool Running { get { return timer.Enabled; } }

        public void To(int value, int milliseconds)
        {
            from = Read();
            to = value;
            durationMs = Math.Max(1, milliseconds);
            startedMs = Now();
            timer.Stop();
            timer.Start();
        }

        public void Stop() { timer.Stop(); }

        private static double Now() { return DateTime.Now.Ticks / 10000.0; }

        public static double EaseOutBack(double t)
        {
            if (t >= 1) { return 1; }
            const double c1 = 1.70158;
            const double c3 = c1 + 1;
            return 1 + c3 * Math.Pow(t - 1, 3) + c1 * Math.Pow(t - 1, 2);
        }

        private int Read() { return (int)(vertical ? TopProperty : WidthProperty).GetValue(target, null); }

        private void Write(int value)
        {
            (vertical ? TopProperty : WidthProperty).SetValue(target, value, null);
        }

        private void Step()
        {
            double t = Math.Min(1.0, (Now() - startedMs) / durationMs);
            int value = (int)Math.Round(from + (to - from) * EaseOutBack(t));
            if (!vertical && value < 8) { value = 8; }
            Write(value);
            if (t >= 1)
            {
                timer.Stop();
                Write((int)to);
                Action done = Completed;
                if (done != null) { done(); }
            }
        }
    }
}
'@
}
