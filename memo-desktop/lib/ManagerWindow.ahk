class ManagerWindow {
    static instance := ""

    gui := ""
    wvc := ""
    wv := ""
    ready := false

    static Show() {
        if this.instance && this.instance.gui {
            this.instance.gui.Show()
            WinActivate("ahk_id " this.instance.gui.Hwnd)
            return
        }

        this.instance := ManagerWindow()
        this.instance.Open()
    }

    Open() {
        MemoWindow.EnsureEnvironment()

        this.gui := Gui("+Resize +MinSize640x420", "Memo Manager")
        this.gui.OnEvent("Close", (*) => this.OnClose())
        this.gui.OnEvent("Size", (*) => this.OnSize())
        this.gui.Show("w640 h560")

        dllPath := A_ScriptDir "\lib\" (A_PtrSize = 8 ? "64bit" : "32bit") "\WebView2Loader.dll"
        this.wvc := WebView2.create(this.gui.Hwnd, , MemoWindow.environment, , , , dllPath)
        this.wvc.IsVisible := true
        this.wv := this.wvc.CoreWebView2
        settings := this.wv.Settings
        settings.AreDevToolsEnabled := false
        settings.AreDefaultContextMenusEnabled := false
        settings.IsZoomControlEnabled := false
        settings.IsStatusBarEnabled := false
        settings.AreBrowserAcceleratorKeysEnabled := false
        this.wv.add_WebMessageReceived((sender, args) => this.OnWebMessage(sender, args))
        this.wv.Navigate(this.BuildUri())

        if this.wvc
            this.wvc.Fill()
    }

    BuildUri() {
        htmlPath := StrReplace(A_ScriptDir "\ui\index.html", "\", "/")
        base := SubStr(htmlPath, 1, 2) = "//" ? "file:" htmlPath : "file:///" htmlPath
        return base "#manager"
    }

    Hide() {
        if this.gui
            this.gui.Hide()
    }

    OnClose() {
        this.Hide()
        return true
    }

    OnSize(*) {
        if this.wvc
            this.wvc.Fill()
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
        try FileAppend("[" A_Now "] manager ready`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
        this.PushEvent("hostConfig", Map("mode", "manager"))
    }

    PushEvent(method, params) {
        if !this.wv
            return
        this.wv.PostWebMessageAsJson(JSON.stringify(Map("kind", "event", "method", method, "params", params)))
    }

    Reply(reqId, ok, result) {
        if !this.wv
            return
        this.wv.PostWebMessageAsJson(JSON.stringify(Map("kind", "response", "id", reqId, "ok", ok, "result", result)))
    }
}
