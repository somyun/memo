; ShowDesktopOverride.ahk
; Single-process Show Desktop replacement for Memo Desktop.

class ShowDesktopOverride {
    static CORNER_BTN_WIDTH := 12
    static started := false
    static isDesktopShown := false
    static touchedWindows := []
    static orderSnapshot := []
    static busy := false
    static previousActiveHwnd := 0
    static hook := 0
    static hookCb := 0
    static enumResult := []

    static Start() {
        if this.started
            return

        this.started := true
        Hotkey("#d", (*) => ShowDesktopOverride.ToggleShowDesktop(), "On")
        this.hookCb := CallbackCreate(ShowDesktopOverride_MouseHookProc, "Fast", 3)
        this.hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", this.hookCb, "ptr", 0, "uint", 0, "ptr")
    }

    static Stop(restoreWindows := true) {
        if !this.started
            return

        try Hotkey("#d", "Off")
        if this.hook
            DllCall("UnhookWindowsHookEx", "ptr", this.hook)
        if this.hookCb
            CallbackFree(this.hookCb)

        this.hook := 0
        this.hookCb := 0

        if restoreWindows && this.isDesktopShown
            this.RestoreWindows()
        else if this.isDesktopShown {
            this.touchedWindows := []
            this.orderSnapshot := []
            this.isDesktopShown := false
        }

        this.started := false
    }

    static MouseHookProc(nCode, wParam, lParam) {
        if (nCode >= 0 && (wParam = 0x201 || wParam = 0x202)) {
            x := NumGet(lParam, 0, "Int")
            y := NumGet(lParam, 4, "Int")
            if this.InShowDesktopZone(x, y) {
                if (wParam = 0x202)
                    SetTimer(() => ShowDesktopOverride.ToggleShowDesktop(), -1)
                return 1
            }
        }

        return DllCall("CallNextHookEx", "ptr", this.hook, "int", nCode, "ptr", wParam, "ptr", lParam, "ptr")
    }

    static ToggleShowDesktop(*) {
        if this.busy
            return

        this.busy := true
        try {
            if (this.isDesktopShown && !this.AllTouchedStillMinimized()) {
                this.isDesktopShown := false
                this.touchedWindows := []
                this.orderSnapshot := []
            }

            if this.isDesktopShown
                this.RestoreWindows()
            else
                this.MinimizeWindows()
        } finally {
            this.busy := false
        }
    }

    static MinimizeWindows() {
        this.previousActiveHwnd := DllCall("GetForegroundWindow", "ptr")
        this.orderSnapshot := this.GetTrackedWindows()
        this.touchedWindows := []

        for hwnd in this.orderSnapshot {
            if this.IsProtectedWindow(hwnd)
                continue

            if DllCall("IsWindow", "ptr", hwnd) && !DllCall("IsIconic", "ptr", hwnd) {
                DllCall("ShowWindow", "ptr", hwnd, "int", 6) ; SW_MINIMIZE
                this.touchedWindows.Push(hwnd)
            }
        }

        this.isDesktopShown := true
    }

    static RestoreWindows() {
        for hwnd in this.touchedWindows {
            if DllCall("IsWindow", "ptr", hwnd)
                DllCall("ShowWindow", "ptr", hwnd, "int", 4) ; SW_SHOWNOACTIVATE
        }

        this.RestoreZOrder()
        MemoWindowManager.EnforcePinnedTopMost()

        if DllCall("IsWindow", "ptr", this.previousActiveHwnd)
            WinActivate("ahk_id " this.previousActiveHwnd)

        this.touchedWindows := []
        this.orderSnapshot := []
        this.isDesktopShown := false
    }

    static RestoreZOrder() {
        valid := []
        for hwnd in this.orderSnapshot {
            if this.IsNormalRestoreCandidate(hwnd)
                valid.Push(hwnd)
        }

        if (valid.Length <= 1)
            return

        SWP_NOSIZE := 0x0001
        SWP_NOMOVE := 0x0002
        SWP_NOACTIVATE := 0x0010
        SWP_NOOWNERZORDER := 0x0200
        flags := SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER

        hdwp := DllCall("BeginDeferWindowPos", "int", valid.Length, "ptr")
        loop (valid.Length - 1) {
            if !hdwp
                break

            i := A_Index
            target := valid[i + 1]
            insertAfter := valid[i]
            hdwp := DllCall("DeferWindowPos", "ptr", hdwp,
                "ptr", target, "ptr", insertAfter,
                "int", 0, "int", 0, "int", 0, "int", 0,
                "uint", flags, "ptr")
        }

        if hdwp
            DllCall("EndDeferWindowPos", "ptr", hdwp)
    }

    static AllTouchedStillMinimized() {
        for hwnd in this.touchedWindows {
            if DllCall("IsWindow", "ptr", hwnd) && !DllCall("IsIconic", "ptr", hwnd)
                return false
        }
        return true
    }

    static GetTrackedWindows() {
        this.enumResult := []
        cb := CallbackCreate(ShowDesktopOverride_EnumWindowsProc, "", 2)
        DllCall("EnumWindows", "ptr", cb, "ptr", 0)
        CallbackFree(cb)
        return this.enumResult.Clone()
    }

    static IsNormalRestoreCandidate(hwnd) {
        if !DllCall("IsWindow", "ptr", hwnd)
            return false
        if this.IsWindowTopMost(hwnd)
            return false
        if this.IsProtectedWindow(hwnd) {
            try {
                if MemoWindowManager.IsPinnedHwnd(hwnd)
                    return false
            }
        }
        return true
    }

    static IsWindowTopMost(hwnd) {
        static GWL_EXSTYLE := -20
        static WS_EX_TOPMOST := 0x8
        exStyle := DllCall("GetWindowLong", "ptr", hwnd, "int", GWL_EXSTYLE, "int")
        return (exStyle & WS_EX_TOPMOST) != 0
    }

    static EnumWindowsProc(hwnd, lParam) {
        try {
            if this.IsProtectedWindow(hwnd) || this.IsTrackedWindow(hwnd)
                this.enumResult.Push(hwnd)
        }
        return true
    }

    static IsTrackedWindow(hwnd) {
        static GWL_EXSTYLE := -20
        static WS_EX_TOOLWINDOW := 0x80
        static WS_EX_APPWINDOW := 0x40000
        static GW_OWNER := 4
        static DWMWA_CLOAKED := 14

        if (hwnd = A_ScriptHwnd)
            return false

        if !DllCall("IsWindowVisible", "ptr", hwnd)
            return false

        cloaked := Buffer(4, 0)
        DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", DWMWA_CLOAKED, "ptr", cloaked.Ptr, "uint", 4)
        if NumGet(cloaked, 0, "UInt") != 0
            return false

        try cls := WinGetClass("ahk_id " hwnd)
        catch
            return false

        if (cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd" || cls = "Progman" || cls = "WorkerW")
            return false

        exStyle := DllCall("GetWindowLong", "ptr", hwnd, "int", GWL_EXSTYLE, "int")
        owner := DllCall("GetWindow", "ptr", hwnd, "uint", GW_OWNER, "ptr")
        if (owner && !(exStyle & WS_EX_APPWINDOW))
            return false

        if ((exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW))
            return false

        if DllCall("GetWindowTextLength", "ptr", hwnd, "int") = 0
            return false

        return true
    }

    static IsProtectedWindow(hwnd) {
        try return MemoWindowManager.IsProtectedHwnd(hwnd)
        return false
    }

    static Log(message) {
        try FileAppend("[" A_Now "] showdesktop " message "`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
    }

    static InShowDesktopZone(x, y) {
        for hwnd in WinGetList("ahk_class Shell_TrayWnd") {
            if this.InTrayButtonRect(hwnd, x, y)
                return true
        }

        for hwnd in WinGetList("ahk_class Shell_SecondaryTrayWnd") {
            if this.InTrayButtonRect(hwnd, x, y)
                return true
        }

        return false
    }

    static InTrayButtonRect(hwnd, x, y) {
        WinGetPos(&tx, &ty, &tw, &th, "ahk_id " hwnd)
        return x >= tx + tw - this.CORNER_BTN_WIDTH && x < tx + tw && y >= ty && y < ty + th
    }
}

ShowDesktopOverride_MouseHookProc(nCode, wParam, lParam) {
    return ShowDesktopOverride.MouseHookProc(nCode, wParam, lParam)
}

ShowDesktopOverride_EnumWindowsProc(hwnd, lParam) {
    return ShowDesktopOverride.EnumWindowsProc(hwnd, lParam)
}
