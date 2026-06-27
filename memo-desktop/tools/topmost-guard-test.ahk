#Requires AutoHotkey v2.0
#SingleInstance Force

#Include "..\lib\ShowDesktopOverride.ahk"

class MemoWindowManager {
    static memoHwnd := 0

    static IsProtectedHwnd(hwnd) {
        return hwnd = this.memoHwnd
    }

    static IsPinnedHwnd(hwnd) {
        return hwnd = this.memoHwnd
    }

    static EnforcePinnedTopMost() {
    }
}

memo := Gui("+AlwaysOnTop", "topmost guard memo")
foreign := Gui(, "topmost guard foreign")
memo.Show("x-30000 y-30000 w120 h80 NoActivate")
foreign.Show("x-30000 y-29880 w120 h80 NoActivate")

MemoWindowManager.memoHwnd := memo.Hwnd
ShowDesktopOverride.orderSnapshot := [memo.Hwnd, foreign.Hwnd]

memoCandidate := ShowDesktopOverride.IsNormalRestoreCandidate(memo.Hwnd)
foreignCandidate := ShowDesktopOverride.IsNormalRestoreCandidate(foreign.Hwnd)
foreignBeforeRestore := ShowDesktopOverride.IsWindowTopMost(foreign.Hwnd)
ShowDesktopOverride.RestoreZOrder()
foreignAfterRestore := ShowDesktopOverride.IsWindowTopMost(foreign.Hwnd)
memoStillTopMost := ShowDesktopOverride.IsWindowTopMost(memo.Hwnd)

memo.Destroy()
foreign.Destroy()

ok := !memoCandidate && foreignCandidate && !foreignBeforeRestore && !foreignAfterRestore && memoStillTopMost
FileAppend(
    "memoCandidate=" memoCandidate
    . " foreignCandidate=" foreignCandidate
    . " foreignBeforeRestore=" foreignBeforeRestore
    . " foreignAfterRestore=" foreignAfterRestore
    . " memoStillTopMost=" memoStillTopMost
    . "`n",
    "*"
)

ExitApp(ok ? 0 : 1)
