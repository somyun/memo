; Bridge.ahk — WebView2 JSON 메시지 디스패치
class Bridge {
    static pending := Map()

    static Dispatch(window, msg) {
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
        switch method {
            case "ready":
                window.OnWebReady(params)
            case "dragWindow":
                window.Drag()
            case "closeWindow":
                window.Close()
            case "persistBounds":
                if params.Has("x")
                    window.SaveBounds(params)
            default:
                OutputDebug("Bridge unknown event: " method "`n")
        }
    }
}
