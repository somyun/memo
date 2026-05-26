; DesktopLayer.ahk — Progman / WorkerW 기반 바탕화면 오버레이
class DesktopLayer {
    static workerHwnd := 0
    static defViewHwnd := 0
    static attachMode := ""
    static initialized := false

    static Reset() {
        this.workerHwnd := 0
        this.defViewHwnd := 0
        this.attachMode := ""
        this.initialized := false
    }

    static _DebugLog(message, data := "") {
        ; #region agent log
        try FileAppend('{"sessionId":"013048","location":"DesktopLayer.ahk","message":"' message '","data":'
            . data . ',"timestamp":' . A_TickCount . '}`n', A_ScriptDir "\..\debug-013048.log", "UTF-8")
        ; #endregion
    }

  /**
   * 아이콘 바로 뒤 레이어 HWND를 찾습니다.
   * - workerw-sibling: DefView 호스트 다음 WorkerW (Win10 클래식)
   * - progman-host: DefView가 Progman 직속일 때 (Win11 25H2+)
   * workerw-empty(목록 첫 빈 WorkerW)는 Win+D·슬라이드쇼용 창이라 사용하지 않음
   */
    static Init() {
        if this.initialized
            return this.workerHwnd

        progman := WinExist("ahk_class Progman")
        if !progman
            throw Error("Progman 창을 찾을 수 없습니다.")

        defViewHost := 0
        defViewHwnd := 0
        workerCount := 0
        sibling := 0
        target := 0
        mode := ""

        loop 5 {
            DllCall("SendMessageTimeout", "ptr", progman, "uint", 0x052C, "ptr", 0, "ptr", 0
                , "uint", 0, "uint", 1000, "ptr", 0)
            DllCall("SendMessageTimeout", "ptr", progman, "uint", 0x052C, "ptr", 0, "ptr", 1
                , "uint", 0, "uint", 1000, "ptr", 0)
            Sleep 100

            defViewHost := 0
            defViewHwnd := 0
            workerCount := 0
            for hwnd in WinGetList("ahk_class WorkerW") {
                workerCount++
                dv := DllCall("FindWindowEx", "ptr", hwnd, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0, "ptr")
                if dv {
                    defViewHost := hwnd
                    defViewHwnd := dv
                    break
                }
            }
            if !defViewHost {
                dv := DllCall("FindWindowEx", "ptr", progman, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0, "ptr")
                if dv {
                    defViewHost := progman
                    defViewHwnd := dv
                }
            }
            if !defViewHost
                throw Error("SHELLDLL_DefView(바탕화면 아이콘) 호스트를 찾을 수 없습니다.")

            sibling := DllCall("FindWindowEx", "ptr", 0, "ptr", defViewHost, "str", "WorkerW", "ptr", 0, "ptr")
            if sibling && !DllCall("FindWindowEx", "ptr", sibling, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0, "ptr") {
                target := sibling
                mode := "workerw-sibling"
                break
            }
            if (A_Index = 5 && defViewHost = progman) {
                target := progman
                mode := "progman-host"
            }
        }

        if !target
            throw Error("아이콘 뒤 레이어를 찾을 수 없습니다. (sibling=0, defViewHost=" defViewHost ")")

        this.workerHwnd := target
        this.defViewHwnd := defViewHwnd
        this.attachMode := mode
        this.initialized := true

        ; #region agent log
        this._DebugLog("Init resolved parent", '{"mode":"' mode '","target":' target . ',"defViewHost":' defViewHost
            . ',"sibling":' sibling . ',"defView":' defViewHwnd . ',"workerCount":' workerCount
            . ',"os":"' A_OSVersion . '"}')
        ; #endregion

        return target
    }

    static Attach(hwnd, screenX := 100, screenY := 100, screenW := 300, screenH := 320) {
        parent := this.Init()

        style := WinGetStyle(hwnd)
        exStyle := WinGetExStyle(hwnd)
        style := (style & ~0x00C00000) | 0x40000000
        exStyle |= 0x00000080
        DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr", style)
        DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -20, "ptr", exStyle)

        DllCall("SetParent", "ptr", hwnd, "ptr", parent)

        WinGetPos &wx, &wy, , , "ahk_id " parent
        cx := screenX - wx
        cy := screenY - wy

        SWP_SHOWWINDOW := 0x0040
        SWP_NOMOVE := 0x0002
        SWP_NOSIZE := 0x0001
        SWP_NOACTIVATE := 0x0010
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", cx, "int", cy, "int", screenW, "int", screenH
            , "uint", SWP_SHOWWINDOW)

        ; progman-host: DefView를 메모 위에 두면 마우스가 전부 아이콘 레이어로 가서 클릭 불가
        ; 메모를 DefView 위(Z-order)로 올려 WebView2 입력을 받게 함 (겹치는 영역의 아이콘은 메모 아래)
        if (this.attachMode = "progman-host" && this.defViewHwnd)
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", this.defViewHwnd, "int", 0, "int", 0, "int", 0, "int", 0
                , "uint", SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)

        DllCall("ShowWindow", "ptr", hwnd, "int", 5)
        visible := DllCall("IsWindowVisible", "ptr", hwnd)
        ; #region agent log
        this._DebugLog("Attach ok", '{"hwnd":' hwnd . ',"parent":' parent . ',"mode":"' this.attachMode
            . '","cx":' cx . ',"cy":' cy . ',"visible":' . (visible ? "true" : "false") . '}')
        ; #endregion

        return true
    }

    static Detach(hwnd) {
        DllCall("SetParent", "ptr", hwnd, "ptr", 0)
        style := WinGetStyle(hwnd)
        style := (style & ~0x40000000) | 0x00C80000
        DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr", style)
    }

    static SelfTest() {
        try {
            this.Reset()
            w := this.Init()
            parent := DllCall("GetParent", "ptr", w, "ptr")
            exists := WinExist("ahk_id " w) ? 1 : 0
            return Format("mode={} target={} parent={} defView={} exists={}"
                , this.attachMode, w, parent, this.defViewHwnd, exists)
        } catch as e {
            return "FAIL: " e.Message
        }
    }
}
