#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global SW_MINIMIZE := 6
global SW_SHOWNOACTIVATE := 4
global WM_LBUTTONDOWN := 0x0201
global WM_LBUTTONUP := 0x0202

global isDesktopShown := false
global touchedWindows := []
global capturingWindows := []
global lastCornerTick := 0
global myPid := DllCall("GetCurrentProcessId", "uint")

main := Gui("+AlwaysOnTop +Resize", "Z-order show-desktop test")
main.SetFont("s10", "Segoe UI")
main.AddText("w440", "Win+D or the clock-side corner button toggles the test.")
status := main.AddText("w440", "State: normal")
logBox := main.AddEdit("w440 h260 ReadOnly -Wrap")
main.AddButton("w140", "Toggle").OnEvent("Click", (*) => ToggleDesktop())
main.AddButton("x+8 w140", "Restore").OnEvent("Click", (*) => RestoreDesktop())
main.OnEvent("Close", (*) => ExitApp())
main.Show("w470 h380")

hookCb := CallbackCreate(MouseHook, "Fast", 3)
hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", hookCb, "ptr", 0, "uint", 0, "ptr")

OnExit Cleanup

#d::ToggleDesktop()

MouseHook(nCode, wParam, lParam) {
    global hook, lastCornerTick, WM_LBUTTONDOWN, WM_LBUTTONUP

    if (nCode >= 0 && (wParam = WM_LBUTTONDOWN || wParam = WM_LBUTTONUP)) {
        x := NumGet(lParam, 0, "Int")
        y := NumGet(lParam, 4, "Int")
        WinGetPos(&tx, &ty, &tw, &th, "ahk_class Shell_TrayWnd")

        if (x >= tx + tw - 12 && x < tx + tw && y >= ty && y < ty + th) {
            if (wParam = WM_LBUTTONDOWN && A_TickCount - lastCornerTick > 300) {
                lastCornerTick := A_TickCount
                SetTimer ToggleDesktop, -1
            }
            return 1
        }
    }

    return DllCall("CallNextHookEx", "ptr", hook, "int", nCode, "ptr", wParam, "ptr", lParam, "ptr")
}

ToggleDesktop(*) {
    global isDesktopShown

    if isDesktopShown
        RestoreDesktop()
    else
        ShowDesktop()
}

ShowDesktop() {
    global isDesktopShown, touchedWindows, status, SW_MINIMIZE

    touchedWindows := CaptureWindows()

    for hwnd in touchedWindows
        DllCall("ShowWindow", "ptr", hwnd, "int", SW_MINIMIZE)

    isDesktopShown := true
    status.Text := "State: desktop shown by test (" touchedWindows.Length " windows minimized)"
    Log("ON  minimized " touchedWindows.Length " windows")
}

RestoreDesktop(*) {
    global isDesktopShown, touchedWindows, status, SW_SHOWNOACTIVATE

    for hwnd in touchedWindows {
        if DllCall("IsWindow", "ptr", hwnd)
            DllCall("ShowWindow", "ptr", hwnd, "int", SW_SHOWNOACTIVATE)
    }

    Log("OFF restored " touchedWindows.Length " windows")
    touchedWindows := []
    isDesktopShown := false
    status.Text := "State: normal"
}

CaptureWindows() {
    global capturingWindows

    capturingWindows := []
    cb := CallbackCreate(EnumProc, "Fast", 2)
    DllCall("EnumWindows", "ptr", cb, "ptr", 0)
    CallbackFree(cb)
    return capturingWindows
}

EnumProc(hwnd, lParam) {
    global capturingWindows

    if ShouldTouchWindow(hwnd) {
        capturingWindows.Push(hwnd)
        Log("capture " FormatHwnd(hwnd) "  " WinGetTitle("ahk_id " hwnd))
    }

    return true
}

ShouldTouchWindow(hwnd) {
    global myPid

    if !DllCall("IsWindow", "ptr", hwnd)
        return false

    if !DllCall("IsWindowVisible", "ptr", hwnd)
        return false

    if DllCall("IsIconic", "ptr", hwnd)
        return false

    pid := 0
    DllCall("GetWindowThreadProcessId", "ptr", hwnd, "uint*", &pid)
    if (pid = myPid)
        return false

    try cls := WinGetClass("ahk_id " hwnd)
    catch
        return false

    if (cls = "Shell_TrayWnd" || cls = "Progman" || cls = "WorkerW")
        return false

    try title := WinGetTitle("ahk_id " hwnd)
    catch
        return false

    if (title = "")
        return false

    return true
}

Log(text) {
    global logBox
    logBox.Value .= FormatTime(, "HH:mm:ss") "  " text "`r`n"
    SendMessage(0xB7, 0, 0, , "ahk_id " logBox.Hwnd)
}

FormatHwnd(hwnd) {
    return "0x" Format("{:X}", hwnd)
}

Cleanup(*) {
    global hook, hookCb
    RestoreDesktop()
    DllCall("UnhookWindowsHookEx", "ptr", hook)
    CallbackFree(hookCb)
}
