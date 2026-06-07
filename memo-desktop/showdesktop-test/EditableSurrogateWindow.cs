namespace ShowDesktopTest;

internal sealed class EditableSurrogateWindow : Form
{
    private readonly Func<string> _readText;
    private readonly Action<string> _writeText;
    private readonly Func<Rectangle> _readBounds;
    private readonly Action<Rectangle> _writeBounds;
    private readonly Panel _beaconPanel = new();
    private readonly TextBox _editor = new();
    private bool _syncing;
    private bool _syncingBounds;

    public EditableSurrogateWindow(
        Func<string> readText,
        Action<string> writeText,
        Func<Rectangle> readBounds,
        Action<Rectangle> writeBounds)
    {
        _readText = readText;
        _writeText = writeText;
        _readBounds = readBounds;
        _writeBounds = writeBounds;

        Text = "Show Desktop Test";
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.Sizable;
        StartPosition = FormStartPosition.Manual;
        MinimizeBox = false;
        MaximizeBox = true;
        MinimumSize = new Size(320, 220);
        BackColor = SystemColors.Control;

        BuildLayout();
    }

    public bool IsCreated => IsHandleCreated && !IsDisposed;

    public IntPtr ParentHwnd { get; private set; }

    public Rectangle ScreenBounds { get; private set; } = Rectangle.Empty;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= unchecked((int)NativeMethods.WS_EX_TOOLWINDOW);
            return cp;
        }
    }

    public PixelVisibilityResult ShowOnParent(IntPtr parent, Rectangle screenBounds, string caption)
    {
        ParentHwnd = parent;
        Text = caption;
        ScreenBounds = screenBounds;
        SyncFromMain();

        if (!Visible)
            Show();

        NativeMethods.SetParent(Handle, parent);
        NativeMethods.GetWindowRect(parent, out var parentRect);
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HWND_TOP,
            screenBounds.Left - parentRect.Left,
            screenBounds.Top - parentRect.Top,
            Math.Max(320, screenBounds.Width),
            Math.Max(220, screenBounds.Height),
            NativeMethods.SWP_SHOWWINDOW |
            NativeMethods.SWP_FRAMECHANGED);

        Refresh();
        Thread.Sleep(60);
        return ProbePixels();
    }

    public PixelVisibilityResult ShowTopLevel(Rectangle screenBounds, string caption)
    {
        ParentHwnd = IntPtr.Zero;
        Text = caption;
        var bounds = NormalizeBounds(_readBounds(), screenBounds);
        ScreenBounds = bounds;
        SyncFromMain();

        if (!Visible)
            Show();

        NativeMethods.SetParent(Handle, IntPtr.Zero);
        _syncingBounds = true;
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HWND_TOPMOST,
            bounds.Left,
            bounds.Top,
            Math.Max(320, bounds.Width),
            Math.Max(220, bounds.Height),
            NativeMethods.SWP_SHOWWINDOW |
            NativeMethods.SWP_FRAMECHANGED);
        _syncingBounds = false;

        Activate();
        _editor.Focus();
        Refresh();
        Thread.Sleep(20);
        return ProbePixels();
    }

    public void EnsureTop()
    {
        if (!IsCreated)
            return;

        SyncFromMainIfEditorNotFocused();
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HWND_TOPMOST,
            0,
            0,
            0,
            0,
            NativeMethods.SWP_NOMOVE |
            NativeMethods.SWP_NOSIZE |
            NativeMethods.SWP_SHOWWINDOW);
    }

    public PixelVisibilityResult ProbePixels()
    {
        if (!IsCreated)
            return PixelVisibilityResult.Unavailable("surrogate-not-created");

        var bounds = _beaconPanel.RectangleToScreen(_beaconPanel.ClientRectangle);
        return PixelVisibilityProbe.Sample(bounds, _beaconPanel.BackColor);
    }

    public void HideAndDestroy()
    {
        if (IsDisposed)
            return;

        SyncToMain();
        SyncBoundsToMain();
        Hide();
        ParentHwnd = IntPtr.Zero;
        ScreenBounds = Rectangle.Empty;
    }

    protected override void OnLocationChanged(EventArgs e)
    {
        base.OnLocationChanged(e);
        SyncBoundsToMainIfUserChanged();
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        SyncBoundsToMainIfUserChanged();
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 2,
            Padding = new Padding(14),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var header = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(0, 0, 0, 12),
        };

        _beaconPanel.BackColor = Color.Fuchsia;
        _beaconPanel.Size = new Size(60, 28);
        _beaconPanel.Margin = new Padding(0, 3, 14, 3);
        header.Controls.Add(_beaconPanel);

        _editor.Dock = DockStyle.Fill;
        _editor.Multiline = true;
        _editor.ScrollBars = ScrollBars.Both;
        _editor.WordWrap = false;
        _editor.Font = new Font(FontFamily.GenericMonospace, 9f);
        _editor.AcceptsReturn = true;
        _editor.AcceptsTab = true;
        _editor.TextChanged += (_, _) =>
        {
            if (_syncing)
                return;

            _writeText(_editor.Text);
        };

        root.Controls.Add(header, 0, 0);
        root.Controls.Add(_editor, 0, 1);
        Controls.Add(root);
    }

    private void SyncFromMain()
    {
        _syncing = true;
        try
        {
            var text = _readText();
            if (_editor.Text != text)
                _editor.Text = text;
        }
        finally
        {
            _syncing = false;
        }
    }

    private void SyncFromMainIfEditorNotFocused()
    {
        if (!_editor.Focused)
            SyncFromMain();
    }

    private void SyncToMain()
    {
        _writeText(_editor.Text);
    }

    private void SyncBoundsToMainIfUserChanged()
    {
        if (_syncingBounds || !Visible || WindowState != FormWindowState.Normal)
            return;

        SyncBoundsToMain();
    }

    private void SyncBoundsToMain()
    {
        if (WindowState == FormWindowState.Normal)
        {
            ScreenBounds = Bounds;
            _writeBounds(Bounds);
        }
    }

    private static Rectangle NormalizeBounds(Rectangle preferredBounds, Rectangle fallbackBounds)
    {
        var bounds = preferredBounds.Width > 0 && preferredBounds.Height > 0
            ? preferredBounds
            : fallbackBounds;

        return new Rectangle(
            bounds.Left,
            bounds.Top,
            Math.Max(320, bounds.Width),
            Math.Max(220, bounds.Height));
    }
}
