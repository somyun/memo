; MemoWindowManager.ahk
class MemoWindowManager {
    static windows := Map()

    static NewMemoId() {
        return Format("{:x}{:x}", A_TickCount, Random(0, 0xFFFFFF))
    }

    static Open(memoId := "", restoreBounds := true) {
        global AppConfig
        if (memoId = "")
            memoId := this.NewMemoId()

        if this.windows.Has(memoId) {
            win := this.windows[memoId]
            if win.gui
                win.gui.Show()
            return memoId
        }

        useLayer := AppConfig.Has("desktopLayer") ? AppConfig["desktopLayer"] : true
        win := MemoWindow(memoId, useLayer)
        bounds := restoreBounds ? WindowStateStore.Get(memoId) : ""
        win.Show(bounds)
        this.windows[memoId] := win
        return memoId
    }

    static Unregister(memoId) {
        if this.windows.Has(memoId)
            this.windows.Delete(memoId)
    }

    static RestoreAll() {
        for id in WindowStateStore.AllIds()
            this.Open(id, true)
    }

    static CloseAll() {
        for id, win in this.windows.Clone()
            win.Close()
    }
}
