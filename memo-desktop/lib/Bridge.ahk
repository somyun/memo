; Bridge.ahk — WebView2 JSON 메시지 디스패치
class Bridge {
    static pending := Map()

    static Dispatch(window, msg) {
        global AppIsShuttingDown
        if AppIsShuttingDown
            return

        kind := msg.Has("kind") ? msg["kind"] : "event"
        method := msg.Has("method") ? msg["method"] : ""

        if (kind = "response" && msg.Has("id") && this.pending.Has(msg["id"])) {
            cb := this.pending.Delete(msg["id"])
            try cb.Call(msg)
            return
        }

        if (kind = "request") {
            result := this.HandleRequest(window, method, msg.Has("params") ? msg["params"] : Map())
            if msg.Has("id") {
                window.Reply(msg["id"], result.ok, result.Has("data") ? result["data"] : Map())
            }
            return
        }

        ; event
        this.HandleEvent(window, method, msg.Has("params") ? msg["params"] : Map())
    }

    static HandleRequest(window, method, params) {
        switch method {
            case "dragWindow":
                window.Drag()
                return { ok: true }
            case "getBounds":
                return { ok: true, data: window.GetBounds() }
            case "desktopConfirm":
                return { ok: true, data: this.DesktopConfirm(params) }
            case "desktopMessage":
                this.DesktopMessage(params)
                return { ok: true, data: Map("shown", true) }
            case "saveDataUrl":
                return { ok: true, data: this.SaveDataUrl(params) }
            default:
                return { ok: false, data: Map("error", "unknown method: " method) }
        }
    }

    static HandleEvent(window, method, params) {
        try this.LogEvent(method, params)
        switch method {
            case "ready":
                window.OnWebReady(params)
            case "dragWindow":
                try window.Drag()
            case "closeWindow":
                target := window
                SetTimer(() => Bridge.CloseWindowDeferred(target), -1)
            case "persistBounds":
                if params.Has("x") {
                    try window.SaveBounds(params)
                }
            case "openMemo":
                if params.Has("memoId") {
                    memoId := params["memoId"]
                    SetTimer(() => MemoWindowManager.Open(memoId, true, false, "user"), -1)
                }
            case "closeMemo":
                if params.Has("memoId") {
                    memoId := params["memoId"]
                    SetTimer(() => MemoWindowManager.Close(memoId), -1)
                }
            case "clientError":
                try window.OnClientError(params)
            case "syncVisibleMemos":
                items := []
                if params.Has("items") {
                    for item in params["items"]
                        items.Push(item)
                } else if params.Has("ids") {
                    for id in params["ids"]
                        items.Push(Map("id", id))
                }
                SetTimer(() => MemoWindowManager.SyncVisible(items), -1)
            default:
                OutputDebug("Bridge unknown event: " method "`n")
        }
    }

    static CloseWindowDeferred(window) {
        try window.Close()
        catch {
            try window.Hide()
        }
    }

    static DesktopConfirm(params) {
        message := params.Has("message") ? params["message"] : "계속할까요?"
        title := params.Has("title") ? params["title"] : "Memo Desktop"
        result := MsgBox(message, title, "YesNo Icon?")
        return Map("confirmed", result = "Yes")
    }

    static DesktopMessage(params) {
        message := params.Has("message") ? params["message"] : ""
        title := params.Has("title") ? params["title"] : "Memo Desktop"
        icon := params.Has("icon") ? params["icon"] : "info"
        options := icon = "error" ? "Icon!" : icon = "warn" ? "Icon!" : "Iconi"
        MsgBox(message, title, options)
    }

    static SaveDataUrl(params) {
        fileName := params.Has("fileName") ? this.SafeFileName(params["fileName"]) : "download.bin"
        dataUrl := params.Has("dataUrl") ? params["dataUrl"] : ""
        title := params.Has("title") ? params["title"] : "파일 저장"
        initialPath := A_Desktop "\" fileName
        savePath := FileSelect("S16", initialPath, title, "모든 파일 (*.*)")

        if (savePath = "")
            return Map("saved", false)

        if !RegExMatch(savePath, "\.[^\\/:]+$") {
            ext := this.ExtensionFromName(fileName)
            if (ext != "")
                savePath .= ext
        }

        try {
            this.WriteDataUrl(savePath, dataUrl)
            return Map("saved", true, "path", savePath)
        } catch as e {
            MsgBox("파일 저장 실패:`n" e.Message, "Memo Desktop", "Icon!")
            return Map("saved", false, "error", e.Message)
        }
    }

    static SafeFileName(fileName) {
        safeName := RegExReplace("" fileName, '[\\/:*?"<>|]', "_")
        safeName := Trim(safeName)
        return safeName = "" ? "download.bin" : safeName
    }

    static ExtensionFromName(fileName) {
        if RegExMatch(fileName, "\.[^.\\/:]+$", &match)
            return match[0]
        return ""
    }

    static WriteDataUrl(path, dataUrl) {
        if !RegExMatch(dataUrl, "i)^data:[^,]*;base64,(.*)$", &match)
            throw Error("잘못된 데이터 형식입니다.")

        xml := ComObject("MSXML2.DOMDocument.6.0")
        node := xml.createElement("base64")
        node.dataType := "bin.base64"
        node.text := match[1]

        stream := ComObject("ADODB.Stream")
        stream.Type := 1
        stream.Open()
        stream.Write(node.nodeTypedValue)
        stream.SaveToFile(path, 2)
        stream.Close()
    }

    static LogEvent(method, params) {
        memoId := params.Has("memoId") ? params["memoId"] : ""
        ids := params.Has("ids") ? params["ids"].Length : ""
        try FileAppend("[" A_Now "] bridge event=" method " memoId=" memoId " ids=" ids "`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
    }
}
