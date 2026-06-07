using System.Drawing;
using System.Text;

namespace ShowDesktopTest;

internal sealed class ShowDesktopController : IDisposable
{
    private readonly IntPtr _selfHwnd;
    private readonly Func<PixelVisibilityResult> _pixelProbe;
    private readonly DesktopLayerFallback _desktopLayer;
    private readonly EventLogger _logger = new();
    private readonly SynchronizationContext? _context;
    private readonly NativeMethods.WinEventDelegate _winEventDelegate;
    private readonly List<IntPtr> _hooks = new();
    private readonly List<WindowEventSample> _recentEvents = new();
    private List<WindowInfo> _rollingSnapshot = new();
    private List<WindowInfo> _preShowDesktopSnapshot = new();
    private DateTimeOffset _lastRollingSnapshotAt = DateTimeOffset.MinValue;
    private string _lastSnapshotSource = "none";
    private DateTimeOffset _lastEnsureAt = DateTimeOffset.MinValue;
    private bool _restorePending;
    private int _restoreGeneration;

    public ShowDesktopController(
        IntPtr selfHwnd,
        Func<PixelVisibilityResult> pixelProbe,
        Func<string> readEditorText,
        Action<string> writeEditorText,
        Func<Rectangle> readWindowBounds,
        Action<Rectangle> writeWindowBounds)
    {
        _selfHwnd = selfHwnd;
        _pixelProbe = pixelProbe;
        _desktopLayer = new DesktopLayerFallback(selfHwnd, readEditorText, writeEditorText, readWindowBounds, writeWindowBounds);
        _context = SynchronizationContext.Current;
        _winEventDelegate = WinEventCallback;
        LastEventText = "none";
        LastActionText = "created";
    }

    public event Action? StateChanged;

    public bool InShowDesktop { get; private set; }

    public string LastEventText { get; private set; }

    public string LastActionText { get; private set; }

    public PixelVisibilityResult? LastPixelVisibility { get; private set; }

    public string LogPath => _logger.Path;

    public void Start()
    {
        AddHook(NativeMethods.EVENT_SYSTEM_FOREGROUND, NativeMethods.EVENT_SYSTEM_FOREGROUND);
        AddHook(NativeMethods.EVENT_SYSTEM_MINIMIZESTART, NativeMethods.EVENT_SYSTEM_MINIMIZEEND);
        AddHook(NativeMethods.EVENT_OBJECT_SHOW, NativeMethods.EVENT_OBJECT_HIDE);
        AddHook(NativeMethods.EVENT_OBJECT_CLOAKED, NativeMethods.EVENT_OBJECT_UNCLOAKED);
        Log("controller-started", new { self = NativeMethods.FormatHwnd(_selfHwnd), hookCount = _hooks.Count });
    }

    public void Poll()
    {
        TrimRecentEvents();

        var foreground = NativeMethods.GetForegroundWindow();
        var foregroundClass = NativeMethods.GetWindowClass(foreground);
        var shellForeground = WindowProbe.IsShellWindow(foreground, foregroundClass);
        var foregroundIsManaged = foreground == _selfHwnd || _desktopLayer.IsSurrogateWindow(foreground);
        var self = WindowProbe.GetWindowInfo(_selfHwnd, _selfHwnd, 0, includeDiagnostics: true);
        if (!InShowDesktop && !shellForeground)
            UpdateRollingSnapshot("poll");

        if (!InShowDesktop && LooksLikeShowDesktopState(shellForeground, self))
            EnterShowDesktop("poll-detected", WindowProbe.GetWindowInfo(foreground, _selfHwnd, -1, includeDiagnostics: true));

        if (InShowDesktop)
        {
            EnsureSelfVisible("poll");

            if (!WindowProbe.IsShellWindow(foreground, foregroundClass) && foreground != IntPtr.Zero && !foregroundIsManaged)
                ScheduleRestore("foreground-normal");
        }
    }

    public void CaptureSnapshot(string reason)
    {
        var foreground = NativeMethods.GetForegroundWindow();
        var foregroundIsSelf = foreground == _selfHwnd;
        var usedPassiveSnapshot = foregroundIsSelf && _rollingSnapshot.Count > 0;

        if (!usedPassiveSnapshot)
        {
            _rollingSnapshot = TakeNormalSnapshot();
            _lastRollingSnapshotAt = DateTimeOffset.Now;
            _lastSnapshotSource = foregroundIsSelf ? "active-window-fallback" : reason;
        }
        else
        {
            _lastSnapshotSource = "last-passive-before-this-app-activated";
        }

        LastActionText = $"snapshot:{_lastSnapshotSource} count={_rollingSnapshot.Count}";
        Log("snapshot", new
        {
            reason,
            source = _lastSnapshotSource,
            foreground = NativeMethods.FormatHwnd(foreground),
            foregroundIsSelf,
            count = _rollingSnapshot.Count,
            windows = _rollingSnapshot.Select(WindowProbe.ToLogObject).ToArray()
        });
        StateChanged?.Invoke();
    }

    public string FormatSnapshot()
    {
        var snapshot = _rollingSnapshot.Count > 0 ? _rollingSnapshot : WindowProbe.CaptureZOrder(_selfHwnd, true);
        var sb = new StringBuilder();
        sb.AppendLine($"Snapshot at {_lastRollingSnapshotAt:HH:mm:ss.fff}");
        sb.AppendLine($"Source: {_lastSnapshotSource}");
        sb.AppendLine(WindowProbe.FormatWindows(snapshot));
        sb.AppendLine();
        sb.AppendLine($"Log: {LogPath}");
        return sb.ToString();
    }

    public string ProbeTargets(string reason)
    {
        var selfBefore = WindowProbe.GetWindowInfo(_selfHwnd, _selfHwnd, 0, includeDiagnostics: true);
        if (InShowDesktop || !selfBefore.Visible || selfBefore.Minimized || selfBefore.CloakFlags > 0)
            EnsureSelfVisible($"probe:{reason}");

        var windows = WindowProbe.CaptureZOrder(_selfHwnd, includeDiagnostics: true);
        var targets = windows.Where(WindowProbe.IsProbeTarget).ToList();
        var pixel = ProbePixels($"probe:{reason}");

        Log("probe", new
        {
            reason,
            pixel = ToLogObject(pixel),
            desktopFallback = new
            {
                attached = _desktopLayer.IsAttached,
                mode = _desktopLayer.Mode,
                parent = NativeMethods.FormatHwnd(_desktopLayer.TargetParent)
            },
            targetCount = targets.Count,
            targets = targets.Select(WindowProbe.ToLogObject).ToArray()
        });

        var sb = new StringBuilder();
        sb.AppendLine($"Probe at {DateTimeOffset.Now:HH:mm:ss.fff}");
        sb.AppendLine($"Mode: {(InShowDesktop ? "Show Desktop active" : "Normal")}");
        sb.AppendLine($"Pixel: {(pixel.IsVisible ? "visible" : "not visible")} {pixel.MatchingSamples}/{pixel.TotalSamples} ({pixel.Reason})");
        sb.AppendLine($"Fallback: {(_desktopLayer.IsAttached ? $"attached:{_desktopLayer.Mode}" : "not attached")}");
        sb.AppendLine($"Log: {LogPath}");
        sb.AppendLine();
        sb.AppendLine("Targets");
        sb.AppendLine(WindowProbe.FormatWindows(targets));
        sb.AppendLine();
        sb.AppendLine("Normal z-order");
        sb.AppendLine(WindowProbe.FormatWindows(windows.Where(window => window.IsNormalCandidate || window.IsSelf)));
        return sb.ToString();
    }

    public void ClearLog()
    {
        _logger.Clear();
        LastActionText = "clear-log";
        StateChanged?.Invoke();
    }

    public void ReportHotkeyRegistration(bool snapshotOk, bool probeOk)
    {
        LastActionText = $"hotkeys S={(snapshotOk ? "ok" : "fail")} P={(probeOk ? "ok" : "fail")}";
        Log("hotkey-registration", new
        {
            snapshot = new { ok = snapshotOk, keys = "Ctrl+Alt+S" },
            probe = new { ok = probeOk, keys = "Ctrl+Alt+P" }
        });
        StateChanged?.Invoke();
    }

    public void Dispose()
    {
        if (_desktopLayer.IsAttached)
            _desktopLayer.Detach();

        foreach (var hook in _hooks)
            NativeMethods.UnhookWinEvent(hook);

        _hooks.Clear();
        Log("controller-disposed", new { self = NativeMethods.FormatHwnd(_selfHwnd) });
    }

    private void AddHook(uint eventMin, uint eventMax)
    {
        var hook = NativeMethods.SetWinEventHook(
            eventMin,
            eventMax,
            IntPtr.Zero,
            _winEventDelegate,
            0,
            0,
            NativeMethods.WINEVENT_OUTOFCONTEXT);

        if (hook != IntPtr.Zero)
            _hooks.Add(hook);
        else
            Log("hook-failed", new { eventMin, eventMax });
    }

    private void WinEventCallback(
        IntPtr hWinEventHook,
        uint eventType,
        IntPtr hwnd,
        int idObject,
        int idChild,
        uint dwEventThread,
        uint dwmsEventTime)
    {
        if (_context is not null)
        {
            _context.Post(_ => HandleWinEvent(eventType, hwnd, idObject, idChild, dwEventThread, dwmsEventTime), null);
            return;
        }

        HandleWinEvent(eventType, hwnd, idObject, idChild, dwEventThread, dwmsEventTime);
    }

    private void HandleWinEvent(
        uint eventType,
        IntPtr hwnd,
        int idObject,
        int idChild,
        uint dwEventThread,
        uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero)
            return;

        if (eventType >= NativeMethods.EVENT_OBJECT_SHOW && idObject != NativeMethods.OBJID_WINDOW)
            return;

        var info = WindowProbe.GetWindowInfo(hwnd, _selfHwnd, zOrderRank: -1, includeDiagnostics: true);
        var isManagedSelf = info.IsSelf || _desktopLayer.IsSurrogateWindow(hwnd);
        var logicInfo = isManagedSelf
            ? info with { IsSelf = true, IsNormalCandidate = true }
            : info;
        var name = EventName(eventType);
        LastEventText = $"{name} {info.TitleOrClass}";

        var sample = new WindowEventSample(DateTimeOffset.Now, eventType, hwnd, logicInfo.IsSelf, logicInfo.IsShell, logicInfo.IsNormalCandidate);
        _recentEvents.Add(sample);
        TrimRecentEvents();

        Log("win-event", new
        {
            name,
            eventType,
            idObject,
            idChild,
            hwnd = NativeMethods.FormatHwnd(hwnd),
            info = WindowProbe.ToLogObject(info),
            managedSelf = isManagedSelf,
            dwEventThread,
            dwmsEventTime
        });

        if (!InShowDesktop)
        {
            if (!logicInfo.IsShell &&
                (eventType == NativeMethods.EVENT_SYSTEM_FOREGROUND || eventType == NativeMethods.EVENT_OBJECT_SHOW))
                UpdateRollingSnapshot($"event:{name}");

            if (IsShowDesktopEntry(eventType, logicInfo))
                EnterShowDesktop(name, logicInfo);
        }
        else
        {
            if (logicInfo.IsSelf &&
                (eventType == NativeMethods.EVENT_SYSTEM_MINIMIZESTART ||
                 eventType == NativeMethods.EVENT_OBJECT_HIDE ||
                 eventType == NativeMethods.EVENT_OBJECT_CLOAKED))
            {
                EnsureSelfVisible($"self-{name}");
            }

            if (IsShowDesktopExit(eventType, logicInfo))
                ScheduleRestore($"event:{name}");
        }

        StateChanged?.Invoke();
    }

    private bool IsShowDesktopEntry(uint eventType, WindowInfo info)
    {
        var foreground = NativeMethods.GetForegroundWindow();
        var foregroundClass = NativeMethods.GetWindowClass(foreground);
        var shellForeground = WindowProbe.IsShellWindow(foreground, foregroundClass);
        var hiddenCount = _recentEvents.Count(sample =>
            !sample.IsSelf &&
            sample.IsNormalCandidate &&
            (sample.EventType == NativeMethods.EVENT_SYSTEM_MINIMIZESTART ||
             sample.EventType == NativeMethods.EVENT_OBJECT_HIDE ||
             sample.EventType == NativeMethods.EVENT_OBJECT_CLOAKED));

        return shellForeground && hiddenCount >= 2;
    }

    private bool LooksLikeShowDesktopState(bool shellForeground, WindowInfo self)
    {
        if (!shellForeground)
            return false;

        if (!self.Visible || self.Minimized || self.CloakFlags > 0)
            return true;

        var hiddenCount = _recentEvents.Count(sample =>
            !sample.IsSelf &&
            sample.IsNormalCandidate &&
            (sample.EventType == NativeMethods.EVENT_SYSTEM_MINIMIZESTART ||
             sample.EventType == NativeMethods.EVENT_OBJECT_HIDE ||
             sample.EventType == NativeMethods.EVENT_OBJECT_CLOAKED));

        return hiddenCount >= 2;
    }

    private bool IsShowDesktopExit(uint eventType, WindowInfo info)
    {
        if (info.IsSelf)
            return false;

        if (eventType == NativeMethods.EVENT_SYSTEM_FOREGROUND && !info.IsShell)
            return true;

        var restoredCount = _recentEvents.Count(sample =>
            !sample.IsSelf &&
            sample.IsNormalCandidate &&
            (sample.EventType == NativeMethods.EVENT_SYSTEM_MINIMIZEEND ||
             sample.EventType == NativeMethods.EVENT_OBJECT_SHOW ||
             sample.EventType == NativeMethods.EVENT_OBJECT_UNCLOAKED));

        return restoredCount >= 2;
    }

    private void EnterShowDesktop(string trigger, WindowInfo foreground)
    {
        _preShowDesktopSnapshot = _rollingSnapshot.Count > 0
            ? _rollingSnapshot.ToList()
            : TakeNormalSnapshot();

        InShowDesktop = true;
        LastActionText = $"enter-show-desktop:{trigger}";
        Log("show-desktop-enter", new
        {
            trigger,
            foreground = WindowProbe.ToLogObject(foreground),
            snapshotCount = _preShowDesktopSnapshot.Count,
            snapshotAgeMs = (DateTimeOffset.Now - _lastRollingSnapshotAt).TotalMilliseconds,
            snapshot = _preShowDesktopSnapshot.Select(WindowProbe.ToLogObject).ToArray()
        });

        EnsureSelfVisible("show-desktop-enter");
        EnsurePixelVisible("show-desktop-enter");
    }

    private void ScheduleRestore(string reason)
    {
        if (_restorePending)
            return;

        _restorePending = true;
        LastActionText = $"restore-pending:{reason}";
        Log("restore-scheduled", new { reason });

        _ = Task.Run(async () =>
        {
            await Task.Delay(250).ConfigureAwait(false);
            if (_context is not null)
                _context.Post(_ => RestoreAfterShowDesktop(reason), null);
            else
                RestoreAfterShowDesktop(reason);
        });
    }

    private void RestoreAfterShowDesktop(string reason)
    {
        var generation = ++_restoreGeneration;
        if (_desktopLayer.IsAttached)
        {
            var detach = _desktopLayer.Detach();
            Log("desktop-fallback-detach", new
            {
                reason,
                detach.Ok,
                detach.Mode,
                parent = NativeMethods.FormatHwnd(detach.TargetParent),
                detach.Detail
            });
        }

        InShowDesktop = false;
        EnsureSelfVisible($"restore:{reason}");
        RestoreZOrder(reason);
        _restorePending = false;
        UpdateRollingSnapshot($"restore:{reason}");
        StateChanged?.Invoke();

        ScheduleRestoreSettleRetry(reason, generation);
    }

    private void RestoreZOrder(string reason)
    {
        if (_preShowDesktopSnapshot.Count == 0)
        {
            LastActionText = "restore:no-snapshot";
            Log("restore-zorder-skipped", new { reason, cause = "no-snapshot" });
            return;
        }

        var selfIndex = _preShowDesktopSnapshot.FindIndex(window => window.IsSelf);
        if (selfIndex < 0)
        {
            LastActionText = "restore:self-missing";
            Log("restore-zorder-skipped", new { reason, cause = "self-missing" });
            return;
        }

        var insertAfter = NativeMethods.HWND_TOP;
        WindowInfo? upperNeighbor = null;
        for (var i = selfIndex - 1; i >= 0; i--)
        {
            var candidate = _preShowDesktopSnapshot[i];
            var current = WindowProbe.GetWindowInfo(candidate.Hwnd, _selfHwnd, candidate.ZOrderRank, includeDiagnostics: true);
            if (current.Hwnd != IntPtr.Zero && (current.Visible || current.Minimized) && !current.IsShell)
            {
                insertAfter = candidate.Hwnd;
                upperNeighbor = candidate;
                break;
            }
        }

        var ok = upperNeighbor is null
            ? ForceTopWithoutStayingTopMost()
            : NativeMethods.SetWindowPos(
                _selfHwnd,
                insertAfter,
                0,
                0,
                0,
                0,
                NativeMethods.SWP_NOMOVE |
                NativeMethods.SWP_NOSIZE |
                NativeMethods.SWP_NOACTIVATE |
                NativeMethods.SWP_SHOWWINDOW);

        var self = WindowProbe.GetWindowInfo(_selfHwnd, _selfHwnd, 0, includeDiagnostics: true);
        LastActionText = $"restore-zorder:{(ok ? "ok" : "fail")}";
        Log("restore-zorder", new
        {
            reason,
            ok,
            insertAfter = upperNeighbor is null ? "HWND_TOP" : NativeMethods.FormatHwnd(upperNeighbor.Hwnd),
            upperNeighbor = upperNeighbor is null ? null : WindowProbe.ToLogObject(upperNeighbor),
            self = WindowProbe.ToLogObject(self)
        });
    }

    private void ScheduleRestoreSettleRetry(string reason, int generation)
    {
        _ = Task.Run(async () =>
        {
            await Task.Delay(450).ConfigureAwait(false);
            if (_context is not null)
                _context.Post(_ => RestoreZOrderAfterShellSettle(reason, generation), null);
            else
                RestoreZOrderAfterShellSettle(reason, generation);
        });
    }

    private void RestoreZOrderAfterShellSettle(string reason, int generation)
    {
        if (generation != _restoreGeneration || InShowDesktop || _restorePending)
            return;

        RestoreZOrder($"{reason}:settle-retry");
        UpdateRollingSnapshot($"settle-retry:{reason}");
    }

    private bool ForceTopWithoutStayingTopMost()
    {
        var topMostOk = NativeMethods.SetWindowPos(
            _selfHwnd,
            NativeMethods.HWND_TOPMOST,
            0,
            0,
            0,
            0,
            NativeMethods.SWP_NOMOVE |
            NativeMethods.SWP_NOSIZE |
            NativeMethods.SWP_NOACTIVATE |
            NativeMethods.SWP_SHOWWINDOW);

        var notTopMostOk = NativeMethods.SetWindowPos(
            _selfHwnd,
            NativeMethods.HWND_NOTOPMOST,
            0,
            0,
            0,
            0,
            NativeMethods.SWP_NOMOVE |
            NativeMethods.SWP_NOSIZE |
            NativeMethods.SWP_NOACTIVATE |
            NativeMethods.SWP_SHOWWINDOW);

        return topMostOk && notTopMostOk;
    }

    private void EnsureSelfVisible(string reason)
    {
        if (InShowDesktop && _desktopLayer.IsUsingTopLevelSurrogate)
        {
            EnsurePixelVisible($"surrogate-only:{reason}");
            return;
        }

        var now = DateTimeOffset.Now;
        if (now - _lastEnsureAt < TimeSpan.FromMilliseconds(120))
            return;

        _lastEnsureAt = now;
        var before = WindowProbe.GetWindowInfo(_selfHwnd, _selfHwnd, 0, includeDiagnostics: true);
        var firstShowOk = NativeMethods.ShowWindowAsync(_selfHwnd, NativeMethods.SW_SHOWNOACTIVATE);
        var firstPosOk = NativeMethods.SetWindowPos(
            _selfHwnd,
            NativeMethods.HWND_TOP,
            0,
            0,
            0,
            0,
            NativeMethods.SWP_NOMOVE |
            NativeMethods.SWP_NOSIZE |
            NativeMethods.SWP_NOACTIVATE |
            NativeMethods.SWP_SHOWWINDOW);
        var afterFirst = WindowProbe.GetWindowInfo(_selfHwnd, _selfHwnd, 0, includeDiagnostics: true);

        var usedRestoreFallback = false;
        var restoreOk = false;
        var secondPosOk = false;
        if (!afterFirst.Visible || afterFirst.Minimized || afterFirst.CloakFlags > 0)
        {
            usedRestoreFallback = true;
            restoreOk = NativeMethods.ShowWindowAsync(_selfHwnd, NativeMethods.SW_RESTORE);
            secondPosOk = NativeMethods.SetWindowPos(
                _selfHwnd,
                NativeMethods.HWND_TOP,
                0,
                0,
                0,
                0,
                NativeMethods.SWP_NOMOVE |
                NativeMethods.SWP_NOSIZE |
                NativeMethods.SWP_NOACTIVATE |
                NativeMethods.SWP_SHOWWINDOW);
        }

        var after = WindowProbe.GetWindowInfo(_selfHwnd, _selfHwnd, 0, includeDiagnostics: true);
        var pixel = ProbePixels($"ensure:{reason}");

        LastActionText = $"ensure:{reason}:{(after.Visible && !after.Minimized && after.CloakFlags == 0 ? "ok" : "check-log")}";
        Log("ensure-self-visible", new
        {
            reason,
            firstShowMode = NativeMethods.SW_SHOWNOACTIVATE,
            firstShowOk,
            firstPosOk,
            usedRestoreFallback,
            restoreOk,
            secondPosOk,
            before = WindowProbe.ToLogObject(before),
            afterFirst = WindowProbe.ToLogObject(afterFirst),
            after = WindowProbe.ToLogObject(after),
            pixel = ToLogObject(pixel),
            desktopFallback = new
            {
                attached = _desktopLayer.IsAttached,
                mode = _desktopLayer.Mode,
                parent = NativeMethods.FormatHwnd(_desktopLayer.TargetParent)
            }
        });

        if (InShowDesktop)
            EnsurePixelVisible($"ensure:{reason}");
    }

    private void EnsurePixelVisible(string reason)
    {
        var before = ProbePixels($"pixel-check:{reason}");
        if (before.IsVisible)
        {
            if (_desktopLayer.IsAttached)
                _desktopLayer.EnsureTop();
            return;
        }

        var attach = _desktopLayer.AttachBest(_pixelProbe);
        if (attach.Ok)
            _desktopLayer.EnsureTop();

        if (!_desktopLayer.IsUsingTopLevelSurrogate)
            NativeMethods.ShowWindowAsync(_selfHwnd, NativeMethods.SW_SHOWNOACTIVATE);

        var after = ProbePixels($"pixel-after-fallback:{reason}");
        LastActionText = $"pixel-fallback:{reason}:{(after.IsVisible ? "visible" : "not-visible")}";
        Log("desktop-fallback-attach", new
        {
            reason,
            attach.Ok,
            attach.Mode,
            parent = NativeMethods.FormatHwnd(attach.TargetParent),
            attach.Detail,
            attempts = attach.Attempts.Select(ToLogObject).ToArray(),
            before = ToLogObject(before),
            after = ToLogObject(after)
        });
    }

    private PixelVisibilityResult ProbePixels(string reason)
    {
        var result = _desktopLayer.UsesSurrogate
            ? _desktopLayer.ProbeSurrogatePixels()
            : _pixelProbe();
        LastPixelVisibility = result;
        Log("pixel-visibility", new
        {
            reason,
            result = ToLogObject(result)
        });
        return result;
    }

    private void UpdateRollingSnapshot(string reason)
    {
        if (DateTimeOffset.Now - _lastRollingSnapshotAt < TimeSpan.FromMilliseconds(750))
            return;

        _rollingSnapshot = TakeNormalSnapshot();
        _lastRollingSnapshotAt = DateTimeOffset.Now;
        _lastSnapshotSource = $"passive:{reason}";
        LastActionText = $"tracking:{reason} count={_rollingSnapshot.Count}";
    }

    private List<WindowInfo> TakeNormalSnapshot()
    {
        return WindowProbe.CaptureZOrder(_selfHwnd, includeDiagnostics: true)
            .Where(window => (window.IsNormalCandidate && window.Visible) || window.IsSelf)
            .ToList();
    }

    private void TrimRecentEvents()
    {
        var cutoff = DateTimeOffset.Now - TimeSpan.FromMilliseconds(1500);
        _recentEvents.RemoveAll(sample => sample.Timestamp < cutoff);
    }

    private void Log(string type, object payload)
    {
        _logger.Write(type, payload);
    }

    private static object ToLogObject(PixelVisibilityResult result)
    {
        return new
        {
            result.IsVisible,
            bounds = new
            {
                result.ScreenBounds.Left,
                result.ScreenBounds.Top,
                result.ScreenBounds.Width,
                result.ScreenBounds.Height
            },
            expected = ColorToString(result.ExpectedColor),
            sampled = result.SampledColors.Select(ColorToString).ToArray(),
            result.MatchingSamples,
            result.TotalSamples,
            result.Reason
        };
    }

    private static object ToLogObject(DesktopAttachAttempt attempt)
    {
        return new
        {
            attempt.Mode,
            parent = NativeMethods.FormatHwnd(attempt.TargetParent),
            attempt.MoveOk,
            attempt.PixelVisible,
            attempt.MatchingSamples,
            attempt.TotalSamples,
            attempt.Detail
        };
    }

    private static string ColorToString(Color color)
    {
        if (color.IsEmpty)
            return "empty";

        return $"#{color.R:X2}{color.G:X2}{color.B:X2}";
    }

    private static string EventName(uint eventType)
    {
        return eventType switch
        {
            NativeMethods.EVENT_SYSTEM_FOREGROUND => "foreground",
            NativeMethods.EVENT_SYSTEM_MINIMIZESTART => "minimize-start",
            NativeMethods.EVENT_SYSTEM_MINIMIZEEND => "minimize-end",
            NativeMethods.EVENT_OBJECT_SHOW => "show",
            NativeMethods.EVENT_OBJECT_HIDE => "hide",
            NativeMethods.EVENT_OBJECT_CLOAKED => "cloaked",
            NativeMethods.EVENT_OBJECT_UNCLOAKED => "uncloaked",
            _ => $"event-{eventType:X}"
        };
    }

    private sealed record WindowEventSample(
        DateTimeOffset Timestamp,
        uint EventType,
        IntPtr Hwnd,
        bool IsSelf,
        bool IsShell,
        bool IsNormalCandidate);
}
