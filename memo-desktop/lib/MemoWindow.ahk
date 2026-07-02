; MemoWindow.ahk — 단일 메모 WebView2 호스트 창
class MemoWindow {
    static environment := 0
    static environmentReady := false

    id := ""
    gui := ""
    wvc := ""
    wv := ""
    useDesktopLayer := true
    createIfMissing := false
    ready := false
    visible := false
    _wmMoveHandler := ""
    _readyTimer := ""
    _showOptions := ""
    _initialX := 0
    _initialY := 0
    _initialW := 0
    _initialH := 0
    pinned := false
    pinnedAt := 0

    __New(memoId, useDesktopLayer := true, createIfMissing := false) {
        this.id := memoId
        this.useDesktopLayer := useDesktopLayer
        this.createIfMissing := createIfMissing
    }

    static EnsureEnvironment() {
        if this.environmentReady
            return
        dllPath := A_ScriptDir "\lib\" (A_PtrSize = 8 ? "64bit" : "32bit") "\WebView2Loader.dll"
        dataDir := EnvGet("LOCALAPPDATA") "\MemoDesktop\WebView2"
        if !DirExist(dataDir)
            DirCreate(dataDir)
        this.environment := WebView2.CreateEnvironmentAsync(, dataDir, , dllPath).await()
        this.environmentReady := true
    }

    Show(bounds := "") {
        global AppConfig
        MemoWindow.EnsureEnvironment()

        w := AppConfig.Has("defaultWidth") ? AppConfig["defaultWidth"] : 300
        h := AppConfig.Has("defaultHeight") ? AppConfig["defaultHeight"] : 320
        x := 120, y := 120
        if (bounds != "" && bounds is Map) {
            if bounds.Has("x")
                x := bounds["x"], y := bounds["y"], w := bounds["w"], h := bounds["h"]
        }

        this._initialX := x
        this._initialY := y
        this._initialW := w
        this._initialH := h
        this._showOptions := "x" x " y" y " w" w " h" h

        this.gui := Gui("-Caption +Resize +MinSize250x160", "Memo " this.id)
        this.gui.BackColor := "FEF9C3"
        this.gui.OnEvent("Close", (*) => this.Close())
        this.gui.OnEvent("Size", (*) => this.OnSize())
        this._wmMoveHandler := (wParam, lParam, msg, hwnd) => this.OnWmMove(hwnd)
        OnMessage(0x3, this._wmMoveHandler)

        ; WebView2는 숨겨진 parent에서 navigation이 멈출 수 있어, 화면 밖에서 먼저 준비시킨다.
        this.gui.Show("x-32000 y-32000 w" w " h" h " NoActivate")

        dllPath := A_ScriptDir "\lib\" (A_PtrSize = 8 ? "64bit" : "32bit") "\WebView2Loader.dll"
        parentHwnd := DllCall("GetParent", "ptr", this.gui.Hwnd, "ptr")
        ; #region agent log
        try FileAppend('{"sessionId":"013048","location":"MemoWindow.ahk:Show","message":"before WebView2.create","data":{"hwnd":'
            . this.gui.Hwnd . ',"parent":' parentHwnd . ',"visible":' . (DllCall("IsWindowVisible", "ptr", this.gui.Hwnd) ? "true" : "false")
            . ',"mode":"' DesktopLayer.attachMode '"},"timestamp":' . A_TickCount . '}`n'
            , A_ScriptDir "\..\debug-013048.log", "UTF-8")
        ; #endregion
        try {
            this.wvc := WebView2.create(this.gui.Hwnd, , MemoWindow.environment, , , , dllPath)
        } catch as e {
            ; #region agent log
            try FileAppend('{"sessionId":"013048","location":"MemoWindow.ahk:Show","message":"WebView2.create failed","data":{"err":"'
                . StrReplace(e.Message, '"', "'") . '"},"timestamp":' . A_TickCount . '}`n'
                , A_ScriptDir "\..\debug-013048.log", "UTF-8")
            ; #endregion
            if this.useDesktopLayer {
                DesktopLayer.Detach(this.gui.Hwnd)
                this.useDesktopLayer := false
            }
            try {
                this.wvc := WebView2.create(this.gui.Hwnd, , MemoWindow.environment, , , , dllPath)
            } catch as e2 {
                MsgBox("WebView2 초기화 실패:`n" e2.Message, "Memo Desktop", "Icon!")
                this.Close()
                return
            }
        }
        this.wvc.IsVisible := true
        this.wv := this.wvc.CoreWebView2

        settings := this.wv.Settings
        settings.AreDevToolsEnabled := false
        settings.AreDefaultContextMenusEnabled := false
        settings.IsZoomControlEnabled := false
        settings.IsStatusBarEnabled := false
        settings.AreBrowserAcceleratorKeysEnabled := false

        this.wv.add_WebMessageReceived((sender, args) => this.OnWebMessage(sender, args))

        uri := this.BuildUiUri()
        this.Log("navigate " uri)
        this._readyTimer := () => this.OnReadyTimeout()
        SetTimer(this._readyTimer, -7000)
        this.wv.Navigate(uri)

        if this.wvc
            this.wvc.Fill()

        if (VerCompare(A_OSVersion, "6.0") >= 0) {
            margins := Buffer(16, 0)
            NumPut("int", 1, margins, 0)
            NumPut("int", 1, margins, 4)
            NumPut("int", 1, margins, 8)
            NumPut("int", 1, margins, 12)
            DllCall("Dwmapi\DwmExtendFrameIntoClientArea", "ptr", this.gui.Hwnd, "ptr", margins)
        }
    }

    BuildUiUri() {
        htmlPath := StrReplace(A_ScriptDir "\ui\index.html", "\", "/")
        if (SubStr(htmlPath, 1, 2) = "//")
            base := "file:" htmlPath
        else
            base := "file:///" htmlPath
        route := this.createIfMissing ? "new:" this.id : this.id
        return base "#" route
    }

    OnWebMessage(sender, args) {
        jsonStr := args.WebMessageAsJson
        if (jsonStr = "")
            return
        try msg := JSON.parse(jsonStr, , true)
        catch {
            return
        }
        Bridge.Dispatch(this, msg)
    }

    OnWebReady(params) {
        this.ready := true
        if this._readyTimer {
            SetTimer(this._readyTimer, 0)
            this._readyTimer := ""
        }
        this.Reveal()
        bounds := this.GetBounds()
        this.PushEvent("hostConfig", Map(
            "memoId", this.id,
            "desktopLayer", this.useDesktopLayer,
            "host", MemoWindowManager.GetHostInfo(),
            "bounds", bounds
        ))
        this.PushEvent("windowBounds", bounds)
    }

    Reveal() {
        if !this.gui || this.visible
            return

        this.gui.Show(this._showOptions " NoActivate")
        this.visible := true
        this.Log("revealed")

        if this.useDesktopLayer {
            try DesktopLayer.Attach(this.gui.Hwnd, this._initialX, this._initialY, this._initialW, this._initialH)
            catch as e {
                MsgBox("바탕화면 레이어 연결 실패 — 일반 창으로 표시합니다.`n" e.Message, "Memo Desktop", "Icon!")
                this.useDesktopLayer := false
            }
        }

        if this.wvc
            this.wvc.Fill()
    }

    OnReadyTimeout() {
        if this.ready || !this.gui
            return
        this.Log("memo webview ready timeout")
        this.Close()
    }

    OnClientError(params) {
        msg := params.Has("message") ? params["message"] : ""
        src := params.Has("source") ? params["source"] : ""
        line := params.Has("line") ? params["line"] : ""
        this.Log("client error: " msg " source=" src " line=" line)
    }

    Log(message) {
        try FileAppend("[" A_Now "] memo=" this.id " " message "`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
    }

    OnSize(*) {
        if this.wvc
            this.wvc.Fill()
        if this.ready && this.visible
            this.PushEvent("windowBounds", this.GetBounds())
    }

    OnWmMove(hwnd) {
        if !this.gui || hwnd != this.gui.Hwnd
            return
        this.OnMove()
    }

    OnMove(*) {
        if this.ready && this.visible
            SetTimer(() => this.PushEvent("windowBounds", this.GetBounds()), -80)
    }

    GetBounds() {
        if !this.visible {
            return Map("x", this._initialX, "y", this._initialY, "w", this._initialW, "h", this._initialH, "kind", "client")
        }
        this.gui.GetPos(&x, &y, &outerW, &outerH)
        this.gui.GetClientPos(&clientX, &clientY, &w, &h)
        return Map("x", x, "y", y, "w", w, "h", h, "kind", "client")
    }

    SaveBounds(params) {
        if !this.visible
            return
        WindowStateStore.Set(this.id, params)
    }

    SetPinnedState(pinned, pinnedAt := 0, force := false) {
        nextPinned := !!pinned
        nextPinnedAt := pinnedAt ? pinnedAt : 0
        changed := this.pinned != nextPinned || this.pinnedAt != nextPinnedAt
        if (!changed && !force)
            return false

        this.pinned := nextPinned
        this.pinnedAt := nextPinnedAt
        if !this.gui
            return changed
        this.Log("pinned=" (this.pinned ? "true" : "false") " pinnedAt=" this.pinnedAt)
        if this.pinned
            WinSetAlwaysOnTop(1, "ahk_id " this.gui.Hwnd)
        else
            WinSetAlwaysOnTop(0, "ahk_id " this.gui.Hwnd)
        return changed
    }

    RaisePinned() {
        if this.gui && this.pinned
            WinMoveTop("ahk_id " this.gui.Hwnd)
    }

    Drag() {
        if !this.gui
            return
        DllCall("User32\ReleaseCapture")
        PostMessage(0xA1, 2, 0, , this.gui)
    }

    PushEvent(method, params) {
        if !this.wv
            return
        payload := Map("kind", "event", "method", method, "params", params)
        this.wv.PostWebMessageAsJson(JSON.stringify(payload))
    }

    Reply(reqId, ok, result) {
        payload := Map("kind", "response", "id", reqId, "ok", ok, "result", result)
        this.wv.PostWebMessageAsJson(JSON.stringify(payload))
    }

    Close(fast := false) {
        if !this.gui && !this.wvc && !this.wv {
            MemoWindowManager.Unregister(this.id)
            return
        }

        if this._readyTimer {
            SetTimer(this._readyTimer, 0)
            this._readyTimer := ""
        }
        if this._wmMoveHandler {
            OnMessage(0x3, this._wmMoveHandler, 0)
            this._wmMoveHandler := ""
        }
        if this.ready && this.visible
            this.SaveBounds(this.GetBounds())

        wvc := this.wvc
        gui := this.gui
        this.gui := ""
        this.wvc := ""
        this.wv := ""
        this.ready := false
        this.visible := false

        if gui && fast
            try gui.Destroy()
        if wvc && !fast
            try wvc.Close()
        if gui && !fast
            try gui.Destroy()
        MemoWindowManager.Unregister(this.id)
    }
}
