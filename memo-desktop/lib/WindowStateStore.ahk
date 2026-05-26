; WindowStateStore.ahk — 메모별 창 bounds 영속화
class WindowStateStore {
    static path := A_ScriptDir "\data\windows.json"
    static cache := Map()

    static Load() {
        this.cache := Map()
        if !FileExist(this.path)
            return
        try {
            raw := FileRead(this.path, "UTF-8")
            if (Trim(raw) = "")
                return
            data := JSON.parse(raw, , true)
            for id, bounds in data
                this.cache[id] := bounds
        } catch {
            ; 손상 시 빈 캐시로 시작
        }
    }

    static Save() {
        dir := A_ScriptDir "\data"
        if !DirExist(dir)
            DirCreate(dir)
        try FileDelete(this.path)
        FileAppend(JSON.stringify(this.cache), this.path, "UTF-8")
    }

    static Get(memoId) {
        return this.cache.Has(memoId) ? this.cache[memoId] : ""
    }

    static Set(memoId, bounds) {
        this.cache[memoId] := bounds
        SetTimer(() => this.Save(), -300)
    }

    static Remove(memoId) {
        if this.cache.Has(memoId) {
            this.cache.Delete(memoId)
            SetTimer(() => this.Save(), -300)
        }
    }

    static AllIds() {
        ids := []
        for id, _ in this.cache
            ids.Push(id)
        return ids
    }
}
