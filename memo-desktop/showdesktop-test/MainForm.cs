using System.Text;

namespace ShowDesktopTest;

public sealed class MainForm : Form
{
    private const int HotkeySnapshot = 101;
    private const int HotkeyProbe = 102;

    private readonly Label _hwndValue = new();
    private readonly Label _visibleValue = new();
    private readonly Label _minimizedValue = new();
    private readonly Label _cloakedValue = new();
    private readonly Label _rankValue = new();
    private readonly Label _pixelValue = new();
    private readonly Label _modeValue = new();
    private readonly Label _lastEventValue = new();
    private readonly Label _lastActionValue = new();
    private readonly Panel _beaconPanel = new();
    private readonly TextBox _probeText = new();
    private readonly Button _snapshotButton = new();
    private readonly Button _probeButton = new();
    private readonly Button _clearLogButton = new();
    private readonly System.Windows.Forms.Timer _timer = new();

    private ShowDesktopController? _controller;

    public MainForm()
    {
        Text = "Show Desktop Test";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(720, 520);
        Size = new Size(860, 620);
        TopMost = false;
        ShowInTaskbar = true;

        BuildLayout();

        _timer.Interval = 250;
        _timer.Tick += (_, _) =>
        {
            _controller?.Poll();
            RefreshStatus();
        };
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);

        _controller = new ShowDesktopController(
            Handle,
            ProbeBeaconPixels,
            ReadEditorText,
            WriteEditorText,
            ReadWindowBounds,
            WriteWindowBounds);
        _controller.StateChanged += RefreshStatus;
        _controller.Start();
        RegisterHotkeys();
        _controller.CaptureSnapshot("startup");
        _timer.Start();
        RefreshStatus();
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        _timer.Stop();
        UnregisterHotkeys();
        _controller?.Dispose();
        base.OnFormClosed(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == NativeMethods.WM_HOTKEY)
        {
            var id = m.WParam.ToInt32();
            if (id == HotkeySnapshot)
            {
                _controller?.CaptureSnapshot("hotkey-ctrl-alt-s");
                _probeText.Text = _controller?.FormatSnapshot() ?? string.Empty;
                RefreshStatus();
                return;
            }

            if (id == HotkeyProbe)
            {
                _probeText.Text = _controller?.ProbeTargets("hotkey-ctrl-alt-p") ?? string.Empty;
                RefreshStatus();
                return;
            }
        }

        base.WndProc(ref m);
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 3,
            Padding = new Padding(14),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));

        var statusGrid = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 4,
            RowCount = 5,
        };
        statusGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        statusGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        statusGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        statusGrid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));

        AddStatus(statusGrid, 0, 0, "HWND", _hwndValue);
        AddStatus(statusGrid, 2, 0, "Mode", _modeValue);
        AddStatus(statusGrid, 0, 1, "Visible", _visibleValue);
        AddStatus(statusGrid, 2, 1, "Minimized", _minimizedValue);
        AddStatus(statusGrid, 0, 2, "Cloaked", _cloakedValue);
        AddStatus(statusGrid, 2, 2, "Z rank", _rankValue);
        AddStatus(statusGrid, 0, 3, "Pixel", _pixelValue);
        AddStatus(statusGrid, 2, 3, "Beacon", new Label { Text = "fuchsia square", AutoSize = true, Padding = new Padding(0, 4, 8, 4) });
        AddStatus(statusGrid, 0, 4, "Last event", _lastEventValue);
        AddStatus(statusGrid, 2, 4, "Last action", _lastActionValue);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(0, 12, 0, 12),
        };

        _beaconPanel.BackColor = Color.Fuchsia;
        _beaconPanel.Size = new Size(60, 28);
        _beaconPanel.Margin = new Padding(0, 3, 14, 3);

        _snapshotButton.Text = "Snapshot";
        _snapshotButton.AutoSize = true;
        _snapshotButton.Click += (_, _) =>
        {
            _controller?.CaptureSnapshot("manual");
            _probeText.Text = _controller?.FormatSnapshot() ?? string.Empty;
            RefreshStatus();
        };

        _probeButton.Text = "Probe";
        _probeButton.AutoSize = true;
        _probeButton.Click += (_, _) =>
        {
            _probeText.Text = _controller?.ProbeTargets("button") ?? string.Empty;
            RefreshStatus();
        };

        _clearLogButton.Text = "Clear Log";
        _clearLogButton.AutoSize = true;
        _clearLogButton.Click += (_, _) =>
        {
            _controller?.ClearLog();
            _probeText.Text = "Log cleared.";
            RefreshStatus();
        };

        buttons.Controls.AddRange(new Control[] { _beaconPanel, _snapshotButton, _probeButton, _clearLogButton });

        _probeText.Dock = DockStyle.Fill;
        _probeText.Multiline = true;
        _probeText.ScrollBars = ScrollBars.Both;
        _probeText.WordWrap = false;
        _probeText.Font = new Font(FontFamily.GenericMonospace, 9f);

        root.Controls.Add(statusGrid, 0, 0);
        root.Controls.Add(buttons, 0, 1);
        root.Controls.Add(_probeText, 0, 2);
        Controls.Add(root);
    }

    private static void AddStatus(TableLayoutPanel grid, int labelColumn, int row, string label, Label value)
    {
        var name = new Label
        {
            Text = label,
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Padding = new Padding(0, 4, 8, 4),
        };

        value.AutoSize = true;
        value.Anchor = AnchorStyles.Left;
        value.Padding = new Padding(0, 4, 8, 4);

        grid.Controls.Add(name, labelColumn, row);
        grid.Controls.Add(value, labelColumn + 1, row);
    }

    private void RefreshStatus()
    {
        if (InvokeRequired)
        {
            BeginInvoke(RefreshStatus);
            return;
        }

        if (_controller is null)
            return;

        var self = WindowProbe.GetWindowInfo(Handle, Handle, 0, includeDiagnostics: true);
        _hwndValue.Text = NativeMethods.FormatHwnd(Handle);
        _visibleValue.Text = self.Visible ? "true" : "false";
        _minimizedValue.Text = self.Minimized ? "true" : "false";
        _cloakedValue.Text = self.CloakText;
        _rankValue.Text = self.ZOrderRank.ToString();
        _pixelValue.Text = _controller.LastPixelVisibility?.IsVisible == true
            ? $"visible {_controller.LastPixelVisibility.MatchingSamples}/{_controller.LastPixelVisibility.TotalSamples}"
            : $"not visible {_controller.LastPixelVisibility?.MatchingSamples ?? 0}/{_controller.LastPixelVisibility?.TotalSamples ?? 0}";
        _modeValue.Text = _controller.InShowDesktop ? "Show Desktop active" : "Normal";
        _lastEventValue.Text = Truncate(_controller.LastEventText, 44);
        _lastActionValue.Text = Truncate(_controller.LastActionText, 44);

        if (string.IsNullOrWhiteSpace(_probeText.Text))
        {
            var sb = new StringBuilder();
            sb.AppendLine("Ready.");
            sb.AppendLine($"Log: {_controller.LogPath}");
            sb.AppendLine("Recommended: Calculator -> this app -> Paint, wait 1 second, press Ctrl+Alt+S.");
            sb.AppendLine("Then Win+D. If this app disappears, press Ctrl+Alt+P to probe/log and try recovery.");
            _probeText.Text = sb.ToString();
        }
    }

    private void RegisterHotkeys()
    {
        const uint modifiers = NativeMethods.MOD_CONTROL | NativeMethods.MOD_ALT | NativeMethods.MOD_NOREPEAT;
        var snapshotOk = NativeMethods.RegisterHotKey(Handle, HotkeySnapshot, modifiers, NativeMethods.VK_S);
        var probeOk = NativeMethods.RegisterHotKey(Handle, HotkeyProbe, modifiers, NativeMethods.VK_P);

        if (_controller is not null)
            _controller.ReportHotkeyRegistration(snapshotOk, probeOk);
    }

    private void UnregisterHotkeys()
    {
        NativeMethods.UnregisterHotKey(Handle, HotkeySnapshot);
        NativeMethods.UnregisterHotKey(Handle, HotkeyProbe);
    }

    private PixelVisibilityResult ProbeBeaconPixels()
    {
        if (!_beaconPanel.IsHandleCreated || !_beaconPanel.Visible)
            return PixelVisibilityResult.Unavailable("beacon-unavailable");

        var bounds = _beaconPanel.RectangleToScreen(_beaconPanel.ClientRectangle);
        return PixelVisibilityProbe.Sample(bounds, _beaconPanel.BackColor);
    }

    private string ReadEditorText()
    {
        return _probeText.Text;
    }

    private void WriteEditorText(string text)
    {
        if (IsDisposed)
            return;

        if (InvokeRequired)
        {
            BeginInvoke(() => WriteEditorText(text));
            return;
        }

        if (_probeText.Text != text)
            _probeText.Text = text;
    }

    private Rectangle ReadWindowBounds()
    {
        return WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
    }

    private void WriteWindowBounds(Rectangle bounds)
    {
        if (IsDisposed || bounds.Width <= 0 || bounds.Height <= 0)
            return;

        if (InvokeRequired)
        {
            BeginInvoke(() => WriteWindowBounds(bounds));
            return;
        }

        var width = Math.Max(MinimumSize.Width, bounds.Width);
        var height = Math.Max(MinimumSize.Height, bounds.Height);
        NativeMethods.SetWindowPos(
            Handle,
            NativeMethods.HWND_TOP,
            bounds.Left,
            bounds.Top,
            width,
            height,
            NativeMethods.SWP_NOZORDER |
            NativeMethods.SWP_NOACTIVATE |
            NativeMethods.SWP_FRAMECHANGED);

        if (WindowState == FormWindowState.Normal)
            Bounds = new Rectangle(bounds.Left, bounds.Top, width, height);
    }

    private static string Truncate(string value, int maxLength)
    {
        if (value.Length <= maxLength)
            return value;

        return value[..maxLength];
    }
}
