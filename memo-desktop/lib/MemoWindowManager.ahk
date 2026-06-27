; MemoWindowManager.ahk
class MemoWindowManager {
    static windows := Map()
    static manualOpenGrace := Map()
    static visibleMeta := Map()
    static machineKey := ""
    static machineName := ""
    static localInstallId := ""

    static NewMemoId() {
        return Format("{:x}{:x}", A_TickCount, Random(0, 0xFFFFFF))
    }

    static Open(memoId := "", restoreBounds := true, createIfMissing := false, source := "user") {
        global AppConfig
        if (memoId = "") {
            memoId := this.NewMemoId()
            createIfMissing := true
        }

        if (source != "sync")
            this.manualOpenGrace[memoId] := A_TickCount + 3000

        if this.windows.Has(memoId) {
            win := this.windows[memoId]
            if win.gui && win.ready {
                win.gui.Show()
                return memoId
            } else if win.gui {
                ; WebView2 준비 중인 창은 이미 보호 대상이므로 중복 생성하지 않는다.
                this.Log("open ignored while pending memoId=" memoId " source=" source)
                return memoId
            }
        }

        if this.windows.Has(memoId)
            return memoId

        useLayer := AppConfig.Has("desktopLayer") ? AppConfig["desktopLayer"] : false
        win := MemoWindow(memoId, useLayer, createIfMissing)
        bounds := this.GetBoundsFor(memoId, restoreBounds)
        ; Show() 내부 WebView2 await 중 재진입이 발생할 수 있으므로 먼저 맵에 등록한다.
        this.windows[memoId] := win
        try {
            win.Show(bounds)
        } catch as e {
            this.Log("open failed memoId=" memoId " err=" e.Message)
            if this.windows.Has(memoId)
                this.windows.Delete(memoId)
            try win.Close()
        }
        return memoId
    }

    static Close(memoId) {
        if this.windows.Has(memoId)
            this.windows[memoId].Close()
    }

    static SyncVisible(items) {
        keep := Map()
        this.visibleMeta := Map()

        for item in items {
            id := item.Has("id") ? item["id"] : item
            keep[id] := true
            this.visibleMeta[id] := item
            this.Open(id, true, false, "sync")

            if this.windows.Has(id) {
                win := this.windows[id]
                pinned := item.Has("pinned") ? item["pinned"] : false
                pinnedAt := item.Has("pinnedAt") ? item["pinnedAt"] : 0
                win.SetPinnedState(pinned, pinnedAt)
            }
        }

        for id, win in this.windows.Clone() {
            if !keep.Has(id) {
                graceUntil := this.manualOpenGrace.Has(id) ? this.manualOpenGrace[id] : 0
                if (graceUntil && A_TickCount < graceUntil)
                    continue
                if this.manualOpenGrace.Has(id)
                    this.manualOpenGrace.Delete(id)
                win.Close()
            }
        }

        this.ApplyPinnedZOrder()
    }

    static GetBoundsFor(memoId, restoreBounds := true) {
        if restoreBounds && this.visibleMeta.Has(memoId) {
            meta := this.visibleMeta[memoId]
            if meta.Has("bounds") && meta["bounds"] is Map {
                bounds := this.NormalizeBounds(meta["bounds"])
                if bounds
                    return this.ClampBoundsToWorkArea(bounds)
            }
        }
        bounds := restoreBounds ? WindowStateStore.Get(memoId) : ""
        if (bounds is Map)
            return this.ClampBoundsToWorkArea(bounds)
        return bounds
    }

    static NormalizeBounds(bounds) {
        if !(bounds is Map)
            return ""
        for key in ["x", "y", "w", "h"] {
            if !bounds.Has(key)
                return ""
        }
        x := Integer(bounds["x"])
        y := Integer(bounds["y"])
        w := Max(250, Integer(bounds["w"]))
        h := Max(160, Integer(bounds["h"]))
        if !bounds.Has("kind") {
            frameX := DllCall("GetSystemMetrics", "int", 32, "int") + DllCall("GetSystemMetrics", "int", 92, "int")
            frameY := DllCall("GetSystemMetrics", "int", 33, "int") + DllCall("GetSystemMetrics", "int", 92, "int")
            w := Max(250, w - frameX * 2)
            h := Max(160, h - frameY * 2)
        }
        return Map("x", x, "y", y, "w", w, "h", h)
    }

    static ClampBoundsToWorkArea(bounds) {
        if !(bounds is Map)
            return ""

        x := Integer(bounds["x"])
        y := Integer(bounds["y"])
        w := Max(250, Integer(bounds["w"]))
        h := Max(160, Integer(bounds["h"]))

        area := this.FindBestWorkArea(x, y, w, h)
        if !(area is Map)
            return Map("x", Max(0, x), "y", Max(0, y), "w", w, "h", h)

        left := area["left"]
        top := area["top"]
        right := area["right"]
        bottom := area["bottom"]
        maxW := Max(250, right - left)
        maxH := Max(160, bottom - top)
        w := Min(w, maxW)
        h := Min(h, maxH)
        x := Max(left, Min(x, right - w))
        y := Max(top, Min(y, bottom - h))

        return Map("x", x, "y", y, "w", w, "h", h)
    }

    static FindBestWorkArea(x, y, w, h) {
        count := MonitorGetCount()
        best := ""
        hasBest := false
        bestScore := -1
        winCx := x + w / 2
        winCy := y + h / 2

        loop count {
            MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
            overlapW := Max(0, Min(x + w, right) - Max(x, left))
            overlapH := Max(0, Min(y + h, bottom) - Max(y, top))
            overlap := overlapW * overlapH
            areaCx := (left + right) / 2
            areaCy := (top + bottom) / 2
            distance := Abs(winCx - areaCx) + Abs(winCy - areaCy)
            score := overlap > 0 ? overlap + 100000000 : 0 - distance
            if (!hasBest || score > bestScore) {
                hasBest := true
                bestScore := score
                best := Map("left", left, "top", top, "right", right, "bottom", bottom)
            }
        }

        return best
    }

    static GetHostInfo() {
        if (this.machineKey = "") {
            name := EnvGet("COMPUTERNAME")
            if (name = "")
                name := A_ComputerName
            this.machineName := name
            this.localInstallId := this.LoadLocalInstallId()
            this.machineKey := this.localInstallId
        }
        return Map(
            "machineKey", this.machineKey,
            "machineName", this.machineName,
            "localInstallId", this.localInstallId
        )
    }

    static LoadLocalInstallId() {
        dir := EnvGet("LOCALAPPDATA") "\MemoDesktop"
        path := dir "\install-id.txt"
        if FileExist(path) {
            try {
                existing := Trim(FileRead(path, "UTF-8"))
                if RegExMatch(existing, "^[A-Za-z0-9_-]{12,80}$")
                    return existing
            }
        }

        if !DirExist(dir)
            DirCreate(dir)

        id := "install_" Format("{:06x}{:06x}{:06x}{:06x}",
            Random(0, 0xFFFFFF),
            Random(0, 0xFFFFFF),
            Random(0, 0xFFFFFF),
            Random(0, 0xFFFFFF))
        try FileDelete(path)
        try FileAppend(id, path, "UTF-8")
        return id
    }

    static ApplyPinnedZOrder() {
        pinned := []
        for id, win in this.windows {
            if win.pinned
                pinned.Push(win)
        }
        if (pinned.Length = 0)
            return

        ; 오래전에 고정한 창부터 올리고, 가장 최근에 고정한 창을 마지막에 올려 최상단으로 둔다.
        loop pinned.Length {
            i := A_Index
            loop (pinned.Length - i) {
                j := A_Index
                if pinned[j].pinnedAt > pinned[j + 1].pinnedAt {
                    tmp := pinned[j]
                    pinned[j] := pinned[j + 1]
                    pinned[j + 1] := tmp
                }
            }
        }

        for win in pinned
            win.RaisePinned()
        this.Log("applied pinned z-order count=" pinned.Length)
    }

    static Unregister(memoId) {
        if this.windows.Has(memoId)
            this.windows.Delete(memoId)
        if this.manualOpenGrace.Has(memoId)
            this.manualOpenGrace.Delete(memoId)
    }

    static RestoreAll() {
        for id in WindowStateStore.AllIds()
            this.Open(id, true)
    }

    static CloseAll() {
        for id, win in this.windows.Clone()
            win.Close()
    }

    static IsProtectedHwnd(hwnd) {
        for id, win in this.windows {
            if win.gui && win.gui.Hwnd = hwnd
                return true
        }
        return false
    }

    static IsPinnedHwnd(hwnd) {
        for id, win in this.windows {
            if win.gui && win.gui.Hwnd = hwnd
                return win.pinned
        }
        return false
    }

    static EnforcePinnedTopMost() {
        for id, win in this.windows {
            if win.gui
                win.SetPinnedState(win.pinned, win.pinnedAt)
        }
        this.ApplyPinnedZOrder()
    }

    static Log(message) {
        try FileAppend("[" A_Now "] manager " message "`n", A_ScriptDir "\..\debug-013048.log", "UTF-8")
    }
}
