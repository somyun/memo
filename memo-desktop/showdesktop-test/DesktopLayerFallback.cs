namespace ShowDesktopTest;

internal sealed class DesktopLayerFallback
{
    private readonly IntPtr _hwnd;
    private readonly EditableSurrogateWindow _surrogate;
    private NativeMethods.RECT _lastScreenRect;
    private IntPtr _originalParent;
    private long _originalStyle;
    private long _originalExStyle;
    private bool _mainWindowReparented;
    private bool _preferTopLevelSurrogate = true;
    private bool _mainWindowHiddenForSurrogate;

    public DesktopLayerFallback(
        IntPtr hwnd,
        Func<string> readText,
        Action<string> writeText,
        Func<Rectangle> readBounds,
        Action<Rectangle> writeBounds)
    {
        _hwnd = hwnd;
        _surrogate = new EditableSurrogateWindow(readText, writeText, readBounds, writeBounds);
    }

    public bool IsAttached { get; private set; }

    public bool UsesSurrogate => IsAttached && !_mainWindowReparented;

    public string Mode { get; private set; } = "none";

    public IntPtr TargetParent { get; private set; }

    public bool IsSurrogateWindow(IntPtr hwnd)
    {
        return hwnd != IntPtr.Zero && _surrogate.IsCreated && hwnd == _surrogate.Handle;
    }

    public DesktopAttachResult Attach()
    {
        return AttachBest(null);
    }

    public DesktopAttachResult AttachBest(Func<PixelVisibilityResult>? pixelProbe)
    {
        if (IsAttached)
            return new DesktopAttachResult(true, Mode, TargetParent, "already-attached", Array.Empty<DesktopAttachAttempt>());

        NativeMethods.GetWindowRect(_hwnd, out _lastScreenRect);
        var attempts = new List<DesktopAttachAttempt>();
        if (_preferTopLevelSurrogate)
        {
            var preferred = TryTopLevelSurrogate(attempts);
            if (preferred is not null)
                return preferred;
        }

        var candidates = ResolveDesktopParents();
        if (candidates.Count == 0)
            return new DesktopAttachResult(false, "none", IntPtr.Zero, "no-desktop-parent", attempts.ToArray());

        foreach (var candidate in candidates)
        {
            var pixel = _surrogate.ShowOnParent(
                candidate.Target,
                ToRectangle(_lastScreenRect),
                "Show Desktop Test");
            var attempt = new DesktopAttachAttempt(
                candidate.Mode + "-surrogate",
                candidate.Target,
                true,
                pixel.IsVisible,
                pixel.MatchingSamples,
                pixel.TotalSamples,
                "surrogate");
            attempts.Add(attempt);

            if (pixel.IsVisible)
            {
                IsAttached = true;
                Mode = candidate.Mode + "-surrogate";
                TargetParent = candidate.Target;
                _mainWindowReparented = false;
                return new DesktopAttachResult(true, Mode, TargetParent, "surrogate-pixel-visible", attempts.ToArray());
            }
        }

        _surrogate.HideAndDestroy();

        var fallbackSurrogate = TryTopLevelSurrogate(attempts);
        if (fallbackSurrogate is not null)
            return fallbackSurrogate;

        _surrogate.HideAndDestroy();

        _originalParent = NativeMethods.GetParent(_hwnd);
        _originalStyle = NativeMethods.GetWindowLongPtr(_hwnd, NativeMethods.GWL_STYLE).ToInt64();
        _originalExStyle = NativeMethods.GetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE).ToInt64();

        var childStyle = (_originalStyle | NativeMethods.WS_CHILD) & ~NativeMethods.WS_POPUP;
        var childExStyle = _originalExStyle | NativeMethods.WS_EX_TOOLWINDOW;
        NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_STYLE, new IntPtr(childStyle));
        NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE, new IntPtr(childExStyle));

        foreach (var candidate in candidates)
        {
            var previousParent = NativeMethods.SetParent(_hwnd, candidate.Target);
            var moveOk = MoveToCandidate(candidate.Target);
            NativeMethods.ShowWindowAsync(_hwnd, NativeMethods.SW_SHOWNOACTIVATE);
            ForceRepaint();
            Thread.Sleep(160);

            var pixel = pixelProbe?.Invoke();
            var pixelVisible = pixel?.IsVisible ?? true;
            var attempt = new DesktopAttachAttempt(
                candidate.Mode + "-main",
                candidate.Target,
                moveOk,
                pixelVisible,
                pixel?.MatchingSamples ?? -1,
                pixel?.TotalSamples ?? -1,
                $"main-reparent;previous-parent={NativeMethods.FormatHwnd(previousParent)}");
            attempts.Add(attempt);

            if (moveOk && pixelVisible)
            {
                IsAttached = true;
                Mode = candidate.Mode + "-main";
                TargetParent = candidate.Target;
                _mainWindowReparented = true;
                return new DesktopAttachResult(true, candidate.Mode, candidate.Target, "pixel-visible", attempts.ToArray());
            }
        }

        var fallback = candidates[0];
        NativeMethods.SetParent(_hwnd, fallback.Target);
        var fallbackOk = MoveToCandidate(fallback.Target);
        NativeMethods.ShowWindowAsync(_hwnd, NativeMethods.SW_SHOWNOACTIVATE);
        ForceRepaint();

        IsAttached = fallbackOk;
        Mode = fallback.Mode + "-main";
        TargetParent = fallback.Target;
        _mainWindowReparented = true;
        return new DesktopAttachResult(fallbackOk, fallback.Mode, fallback.Target, "no-pixel-visible-candidate", attempts.ToArray());
    }

    public DesktopAttachResult Detach()
    {
        if (!IsAttached)
            return new DesktopAttachResult(true, Mode, TargetParent, "not-attached", Array.Empty<DesktopAttachAttempt>());

        if (!_mainWindowReparented)
        {
            _surrogate.HideAndDestroy();
            RestoreMainWindowIfHidden();
            var targetOnly = TargetParent;
            var modeOnly = Mode;
            IsAttached = false;
            Mode = "none";
            TargetParent = IntPtr.Zero;
            return new DesktopAttachResult(true, modeOnly, targetOnly, "surrogate-destroyed", Array.Empty<DesktopAttachAttempt>());
        }

        _surrogate.HideAndDestroy();
        NativeMethods.GetWindowRect(_hwnd, out var currentRect);
        NativeMethods.SetParent(_hwnd, _originalParent);
        NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_STYLE, new IntPtr(_originalStyle));
        NativeMethods.SetWindowLongPtr(_hwnd, NativeMethods.GWL_EXSTYLE, new IntPtr(_originalExStyle));

        var ok = NativeMethods.SetWindowPos(
            _hwnd,
            NativeMethods.HWND_TOP,
            currentRect.Left,
            currentRect.Top,
            Math.Max(200, currentRect.Width),
            Math.Max(120, currentRect.Height),
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW | NativeMethods.SWP_FRAMECHANGED);

        NativeMethods.ShowWindowAsync(_hwnd, NativeMethods.SW_SHOWNOACTIVATE);
        ForceRepaint();

        var target = TargetParent;
        var mode = Mode;
        IsAttached = false;
        Mode = "none";
        TargetParent = IntPtr.Zero;
        _mainWindowReparented = false;
        return new DesktopAttachResult(ok, mode, target, "detached", Array.Empty<DesktopAttachAttempt>());
    }

    public void EnsureTop()
    {
        if (!IsAttached)
            return;

        if (!_mainWindowReparented)
        {
            _surrogate.EnsureTop();
            return;
        }

        NativeMethods.SetWindowPos(
            _hwnd,
            NativeMethods.HWND_TOP,
            0,
            0,
            0,
            0,
            NativeMethods.SWP_NOMOVE |
            NativeMethods.SWP_NOSIZE |
            NativeMethods.SWP_NOACTIVATE |
            NativeMethods.SWP_SHOWWINDOW);
        ForceRepaint();
    }

    public PixelVisibilityResult ProbeSurrogatePixels()
    {
        return _surrogate.ProbePixels();
    }

    public bool IsUsingTopLevelSurrogate => IsAttached && !_mainWindowReparented;

    private bool MoveToCandidate(IntPtr parent)
    {
        NativeMethods.GetWindowRect(parent, out var parentRect);
        var x = _lastScreenRect.Left - parentRect.Left;
        var y = _lastScreenRect.Top - parentRect.Top;
        return NativeMethods.SetWindowPos(
            _hwnd,
            NativeMethods.HWND_TOP,
            x,
            y,
            Math.Max(200, _lastScreenRect.Width),
            Math.Max(120, _lastScreenRect.Height),
            NativeMethods.SWP_NOACTIVATE | NativeMethods.SWP_SHOWWINDOW | NativeMethods.SWP_FRAMECHANGED);
    }

    private DesktopAttachResult? TryTopLevelSurrogate(List<DesktopAttachAttempt> attempts)
    {
        var topLevelPixel = _surrogate.ShowTopLevel(
            ToRectangle(_lastScreenRect),
            "Show Desktop Test");
        attempts.Add(new DesktopAttachAttempt(
            "top-level-surrogate",
            IntPtr.Zero,
            true,
            topLevelPixel.IsVisible,
            topLevelPixel.MatchingSamples,
            topLevelPixel.TotalSamples,
            "topmost-noactivate-surrogate"));

        if (!topLevelPixel.IsVisible)
        {
            _surrogate.HideAndDestroy();
            return null;
        }

        _preferTopLevelSurrogate = true;
        IsAttached = true;
        Mode = "top-level-surrogate";
        TargetParent = IntPtr.Zero;
        _mainWindowReparented = false;
        HideMainWindowForSurrogate();
        return new DesktopAttachResult(true, Mode, TargetParent, "top-level-surrogate-pixel-visible", attempts.ToArray());
    }

    private void HideMainWindowForSurrogate()
    {
        if (_mainWindowHiddenForSurrogate)
            return;

        NativeMethods.ShowWindowAsync(_hwnd, NativeMethods.SW_HIDE);
        _mainWindowHiddenForSurrogate = true;
    }

    private void RestoreMainWindowIfHidden()
    {
        if (!_mainWindowHiddenForSurrogate)
            return;

        NativeMethods.ShowWindowAsync(_hwnd, NativeMethods.SW_SHOWNOACTIVATE);
        _mainWindowHiddenForSurrogate = false;
    }

    private void ForceRepaint()
    {
        NativeMethods.InvalidateRect(_hwnd, IntPtr.Zero, true);
        NativeMethods.RedrawWindow(
            _hwnd,
            IntPtr.Zero,
            IntPtr.Zero,
            NativeMethods.RDW_INVALIDATE |
            NativeMethods.RDW_INTERNALPAINT |
            NativeMethods.RDW_ERASE |
            NativeMethods.RDW_ALLCHILDREN |
            NativeMethods.RDW_UPDATENOW |
            NativeMethods.RDW_FRAME);
        NativeMethods.UpdateWindow(_hwnd);
        NativeMethods.DwmFlush();
    }

    private static List<DesktopParent> ResolveDesktopParents()
    {
        var parents = new List<DesktopParent>();
        var progman = NativeMethods.FindWindow("Progman", null);
        if (progman == IntPtr.Zero)
            return parents;

        var variants = new[]
        {
            (W: IntPtr.Zero, L: IntPtr.Zero),
            (W: IntPtr.Zero, L: new IntPtr(1)),
            (W: new IntPtr(0xD), L: IntPtr.Zero),
            (W: new IntPtr(0xD), L: new IntPtr(1))
        };

        foreach (var variant in variants)
        {
            NativeMethods.SendMessageTimeout(
                progman,
                0x052C,
                variant.W,
                variant.L,
                NativeMethods.SMTO_NORMAL,
                1000,
                out _);
        }

        var defViewHost = FindDefViewHost(progman);
        if (defViewHost != IntPtr.Zero)
        {
            AddUnique(parents, defViewHost, NativeMethods.GetWindowClass(defViewHost) == "Progman" ? "progman-defview-host" : "workerw-defview-host");

            var sibling = NativeMethods.FindWindowEx(IntPtr.Zero, defViewHost, "WorkerW", null);
            while (sibling != IntPtr.Zero)
            {
                var defView = NativeMethods.FindWindowEx(sibling, IntPtr.Zero, "SHELLDLL_DefView", null);
                if (defView == IntPtr.Zero)
                    AddUnique(parents, sibling, "workerw-sibling-empty");
                else
                    AddUnique(parents, sibling, "workerw-sibling-defview");

                sibling = NativeMethods.FindWindowEx(IntPtr.Zero, sibling, "WorkerW", null);
            }
        }

        NativeMethods.EnumWindows((hwnd, _) =>
        {
            var cls = NativeMethods.GetWindowClass(hwnd);
            if (cls.Equals("WorkerW", StringComparison.OrdinalIgnoreCase))
            {
                var defView = NativeMethods.FindWindowEx(hwnd, IntPtr.Zero, "SHELLDLL_DefView", null);
                AddUnique(parents, hwnd, defView == IntPtr.Zero ? "workerw-enum-empty" : "workerw-enum-defview");
            }

            return true;
        }, IntPtr.Zero);

        AddUnique(parents, progman, "progman-fallback");
        return parents;
    }

    private static void AddUnique(List<DesktopParent> parents, IntPtr hwnd, string mode)
    {
        if (hwnd == IntPtr.Zero || parents.Any(parent => parent.Target == hwnd))
            return;

        parents.Add(new DesktopParent(hwnd, mode));
    }

    private static Rectangle ToRectangle(NativeMethods.RECT rect)
    {
        return new Rectangle(rect.Left, rect.Top, Math.Max(1, rect.Width), Math.Max(1, rect.Height));
    }

    private static IntPtr FindDefViewHost(IntPtr progman)
    {
        var defOnProgman = NativeMethods.FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
        if (defOnProgman != IntPtr.Zero)
            return progman;

        var result = IntPtr.Zero;
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            var defView = NativeMethods.FindWindowEx(hwnd, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView != IntPtr.Zero)
            {
                result = hwnd;
                return false;
            }

            return true;
        }, IntPtr.Zero);

        return result;
    }

    private sealed record DesktopParent(IntPtr Target, string Mode);
}

internal sealed record DesktopAttachAttempt(
    string Mode,
    IntPtr TargetParent,
    bool MoveOk,
    bool PixelVisible,
    int MatchingSamples,
    int TotalSamples,
    string Detail);

internal sealed record DesktopAttachResult(
    bool Ok,
    string Mode,
    IntPtr TargetParent,
    string Detail,
    DesktopAttachAttempt[] Attempts);
