using System.Diagnostics;
using System.Text;

namespace ShowDesktopTest;

internal static class WindowProbe
{
    private static readonly HashSet<string> ShellClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "NotifyIconOverflowWindow",
        "DV2ControlHost",
        "Windows.UI.Core.CoreWindow",
        "MultitaskingViewFrame",
        "XamlExplorerHostIslandWindow"
    };

    public static List<WindowInfo> CaptureZOrder(IntPtr selfHwnd, bool includeDiagnostics)
    {
        var windows = new List<WindowInfo>();
        var hwnd = NativeMethods.GetTopWindow(IntPtr.Zero);
        var rank = 0;

        while (hwnd != IntPtr.Zero)
        {
            windows.Add(GetWindowInfo(hwnd, selfHwnd, rank, includeDiagnostics));
            hwnd = NativeMethods.GetWindow(hwnd, NativeMethods.GW_HWNDNEXT);
            rank++;

            if (rank > 1000)
                break;
        }

        return windows;
    }

    public static WindowInfo GetWindowInfo(IntPtr hwnd, IntPtr selfHwnd, int zOrderRank, bool includeDiagnostics)
    {
        if (hwnd == IntPtr.Zero)
        {
            return new WindowInfo(
                IntPtr.Zero,
                string.Empty,
                string.Empty,
                string.Empty,
                0,
                false,
                false,
                -1,
                zOrderRank,
                false,
                false,
                false,
                0,
                0);
        }

        var title = NativeMethods.GetWindowTitle(hwnd);
        var className = NativeMethods.GetWindowClass(hwnd);
        _ = NativeMethods.GetWindowThreadProcessId(hwnd, out var processId);
        var processName = GetProcessName(processId);
        var visible = NativeMethods.IsWindowVisible(hwnd);
        var minimized = NativeMethods.IsIconic(hwnd);
        var cloakFlags = NativeMethods.GetCloakFlags(hwnd);
        var style = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_STYLE).ToInt64();
        var exStyle = NativeMethods.GetWindowLongPtr(hwnd, NativeMethods.GWL_EXSTYLE).ToInt64();
        var isSelf = hwnd == selfHwnd;
        var isShell = IsShellWindow(hwnd, className);
        var isCandidate = IsNormalCandidate(hwnd, title, className, visible, style, exStyle, isShell, isSelf);

        return new WindowInfo(
            hwnd,
            title,
            className,
            processName,
            processId,
            visible,
            minimized,
            cloakFlags,
            zOrderRank,
            isSelf,
            isShell,
            isCandidate,
            includeDiagnostics ? style : 0,
            includeDiagnostics ? exStyle : 0);
    }

    public static bool IsShellWindow(IntPtr hwnd, string? className = null)
    {
        if (hwnd == IntPtr.Zero)
            return false;

        if (hwnd == NativeMethods.GetShellWindow())
            return true;

        className ??= NativeMethods.GetWindowClass(hwnd);
        return ShellClasses.Contains(className);
    }

    public static bool IsProbeTarget(WindowInfo window)
    {
        if (window.IsSelf)
            return true;

        var haystack = $"{window.ProcessName} {window.Title} {window.ClassName}";
        return haystack.Contains("calc", StringComparison.OrdinalIgnoreCase) ||
               haystack.Contains("calculator", StringComparison.OrdinalIgnoreCase) ||
               haystack.Contains("계산기", StringComparison.OrdinalIgnoreCase) ||
               haystack.Contains("paint", StringComparison.OrdinalIgnoreCase) ||
               haystack.Contains("mspaint", StringComparison.OrdinalIgnoreCase) ||
               haystack.Contains("그림판", StringComparison.OrdinalIgnoreCase);
    }

    public static string FormatWindows(IEnumerable<WindowInfo> windows)
    {
        var sb = new StringBuilder();
        sb.AppendLine("rank | hwnd       | vis | min | cloak     | process          | class/title");
        sb.AppendLine("-----+------------+-----+-----+-----------+------------------+-----------------------------");

        foreach (var window in windows)
        {
            sb.Append(window.ZOrderRank.ToString().PadLeft(4));
            sb.Append(" | ");
            sb.Append(NativeMethods.FormatHwnd(window.Hwnd).PadRight(10));
            sb.Append(" | ");
            sb.Append((window.Visible ? "yes" : "no ").PadRight(3));
            sb.Append(" | ");
            sb.Append((window.Minimized ? "yes" : "no ").PadRight(3));
            sb.Append(" | ");
            sb.Append(window.CloakText.PadRight(9));
            sb.Append(" | ");
            sb.Append(Trim(window.ProcessName, 16).PadRight(16));
            sb.Append(" | ");
            sb.AppendLine(Trim($"{window.ClassName} / {window.Title}", 80));
        }

        return sb.ToString();
    }

    public static object ToLogObject(WindowInfo window)
    {
        return new
        {
            hwnd = NativeMethods.FormatHwnd(window.Hwnd),
            window.Title,
            window.ClassName,
            window.ProcessName,
            window.ProcessId,
            window.Visible,
            window.Minimized,
            window.CloakFlags,
            cloak = window.CloakText,
            window.ZOrderRank,
            window.IsSelf,
            window.IsShell,
            window.IsNormalCandidate,
            style = $"0x{window.Style:X}",
            exStyle = $"0x{window.ExStyle:X}"
        };
    }

    private static bool IsNormalCandidate(
        IntPtr hwnd,
        string title,
        string className,
        bool visible,
        long style,
        long exStyle,
        bool isShell,
        bool isSelf)
    {
        if (isSelf)
            return true;

        if (isShell)
            return false;

        if ((style & NativeMethods.WS_DISABLED) != 0)
            return false;

        if ((exStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0)
            return false;

        if (NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) != IntPtr.Zero)
            return false;

        if (string.IsNullOrWhiteSpace(title) && !className.Equals("ApplicationFrameWindow", StringComparison.OrdinalIgnoreCase))
            return false;

        return true;
    }

    private static string GetProcessName(uint processId)
    {
        if (processId == 0)
            return string.Empty;

        try
        {
            using var process = Process.GetProcessById((int)processId);
            return process.ProcessName;
        }
        catch
        {
            return string.Empty;
        }
    }

    private static string Trim(string value, int maxLength)
    {
        if (value.Length <= maxLength)
            return value;

        return value[..maxLength];
    }
}
