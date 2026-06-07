namespace ShowDesktopTest;

internal sealed record WindowInfo(
    IntPtr Hwnd,
    string Title,
    string ClassName,
    string ProcessName,
    uint ProcessId,
    bool Visible,
    bool Minimized,
    int CloakFlags,
    int ZOrderRank,
    bool IsSelf,
    bool IsShell,
    bool IsNormalCandidate,
    long Style,
    long ExStyle)
{
    public string TitleOrClass => string.IsNullOrWhiteSpace(Title) ? ClassName : Title;

    public string CloakText
    {
        get
        {
            if (CloakFlags < 0)
                return "unknown";

            if (CloakFlags == 0)
                return "none";

            var parts = new List<string>();
            if ((CloakFlags & NativeMethods.DWM_CLOAKED_APP) != 0)
                parts.Add("app");
            if ((CloakFlags & NativeMethods.DWM_CLOAKED_SHELL) != 0)
                parts.Add("shell");
            if ((CloakFlags & NativeMethods.DWM_CLOAKED_INHERITED) != 0)
                parts.Add("inherited");

            return string.Join("+", parts);
        }
    }
}
