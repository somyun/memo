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

    static LogEvent(method, params) {
        memoId := params.Has("memoId") ? params["memoId"] : ""
        ids := params.Has("ids") ? params["ids"].Length : ""
        try FileAppend("[" A_Now "] bridge event=" method " memoId=" memoId " ids=" ids "`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
    }
}
