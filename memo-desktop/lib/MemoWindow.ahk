; MemoWindow.ahk — 단일 메모 WebView2 호스트 창
class MemoWindow {
    static environment := 0
    static environmentReady := false

    id := ""
    gui := ""
    wvc := ""
    wv := ""
    useDesktopLayer := true
    ready := false
    _wmMoveHandler := ""

    __New(memoId, useDesktopLayer := true) {
        this.id := memoId
        this.useDesktopLayer := useDesktopLayer
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

        this.gui := Gui("-Caption +Resize +MinSize250x160", "Memo " this.id)
        this.gui.BackColor := "FEF9C3"
        this.gui.OnEvent("Close", (*) => this.Close())
        this.gui.OnEvent("Size", (*) => this.OnSize())
        this._wmMoveHandler := (wParam, lParam, msg, hwnd) => this.OnWmMove(hwnd)
        OnMessage(0x3, this._wmMoveHandler)

        this.gui.Show("x" x " y" y " w" w " h" h)

        if this.useDesktopLayer {
            try DesktopLayer.Attach(this.gui.Hwnd, x, y, w, h)
            catch as e {
                MsgBox("바탕화면 레이어 연결 실패 — 일반 창으로 표시합니다.`n" e.Message, "Memo Desktop", "Icon!")
                this.useDesktopLayer := false
            }
        }

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
        settings.AreDefaultContextMenusEnabled := false
        settings.IsZoomControlEnabled := false
        settings.IsStatusBarEnabled := false
        settings.AreBrowserAcceleratorKeysEnabled := true

        this.wv.add_WebMessageReceived((sender, args) => this.OnWebMessage(sender, args))

        uri := this.BuildUiUri()
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
        return base "#" this.id
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
        bounds := this.GetBounds()
        this.PushEvent("hostConfig", Map(
            "memoId", this.id,
            "desktopLayer", this.useDesktopLayer,
            "bounds", bounds
        ))
    }

    OnSize(*) {
        if this.wvc
            this.wvc.Fill()
        if this.ready
            this.PushEvent("windowBounds", this.GetBounds())
    }

    OnWmMove(hwnd) {
        if !this.gui || hwnd != this.gui.Hwnd
            return
        this.OnMove()
    }

    OnMove(*) {
        if this.ready
            SetTimer(() => this.PushEvent("windowBounds", this.GetBounds()), -80)
    }

    GetBounds() {
        rect := Buffer(16, 0)
        DllCall("GetWindowRect", "ptr", this.gui.Hwnd, "ptr", rect)
        x := NumGet(rect, 0, "int")
        y := NumGet(rect, 4, "int")
        r := NumGet(rect, 8, "int")
        b := NumGet(rect, 12, "int")
        return Map("x", x, "y", y, "w", r - x, "h", b - y)
    }

    SaveBounds(params) {
        WindowStateStore.Set(this.id, params)
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

    Close() {
        if this._wmMoveHandler {
            OnMessage(0x3, this._wmMoveHandler, 0)
            this._wmMoveHandler := ""
        }
        if this.ready
            this.SaveBounds(this.GetBounds())
        if (this.gui)
            this.gui.Destroy()
        this.gui := ""
        this.wvc := ""
        this.wv := ""
        MemoWindowManager.Unregister(this.id)
    }
}
