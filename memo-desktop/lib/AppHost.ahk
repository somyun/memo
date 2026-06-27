class AppHost {
    static instance := ""

    gui := ""
    wvc := ""
    wv := ""

    static Start() {
        if this.instance
            return

        this.instance := AppHost()
        this.instance.Open()
    }

    static HideAllVisible() {
        if this.instance
            this.instance.PushEvent("hideAllVisible", Map())
    }

    Open() {
        MemoWindow.EnsureEnvironment()

        this.gui := Gui("-Caption +ToolWindow", "Memo Host")
        this.gui.Show("Hide w1 h1")

        dllPath := A_ScriptDir "\lib\" (A_PtrSize = 8 ? "64bit" : "32bit") "\WebView2Loader.dll"
        this.wvc := WebView2.create(this.gui.Hwnd, , MemoWindow.environment, , , , dllPath)
        this.wvc.IsVisible := false
        this.wv := this.wvc.CoreWebView2
        settings := this.wv.Settings
        settings.AreDevToolsEnabled := false
        settings.AreDefaultContextMenusEnabled := false
        settings.IsZoomControlEnabled := false
        settings.IsStatusBarEnabled := false
        settings.AreBrowserAcceleratorKeysEnabled := false
        this.wv.add_WebMessageReceived((sender, args) => this.OnWebMessage(sender, args))
        this.wv.Navigate(this.BuildUri())
    }

    BuildUri() {
        htmlPath := StrReplace(A_ScriptDir "\ui\index.html", "\", "/")
        base := SubStr(htmlPath, 1, 2) = "//" ? "file:" htmlPath : "file:///" htmlPath
        return base "#host"
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
        try FileAppend("[" A_Now "] host ready`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
        this.PushEvent("hostConfig", Map("mode", "host", "host", MemoWindowManager.GetHostInfo()))
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
