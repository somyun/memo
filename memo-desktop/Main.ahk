#Requires AutoHotkey v2.0
#SingleInstance Force
DetectHiddenWindows True

; WebView2: DPI awareness 불일치 시 0x8007139F 발생 방지
try DllCall("SetProcessDpiAwarenessContext", "ptr", -4)

#Include "lib\JSON.ahk"
#Include "lib\WebView2.ahk"
#Include "lib\DesktopLayer.ahk"
#Include "lib\WindowStateStore.ahk"
#Include "lib\Bridge.ahk"
#Include "lib\MemoWindow.ahk"
#Include "lib\MemoWindowManager.ahk"
#Include "lib\ManagerWindow.ahk"
#Include "lib\AppHost.ahk"
#Include "lib\ShowDesktopOverride.ahk"

global AppConfig := Map()

LoadAppConfig()
WindowStateStore.Load()
DesktopLayer.Reset()
ShowDesktopOverride.Start()

; 트레이
A_IconTip := "Memo Desktop"
A_TrayMenu.Delete()
A_TrayMenu.Add("메모 관리", (*) => ManagerWindow.Show())
A_TrayMenu.Add("새 메모", (*) => MemoWindowManager.Open())
A_TrayMenu.Add("모든 메모 숨김", HideAllMemos)
A_TrayMenu.Add("종료", (*) => ExitApp())
A_TrayMenu.Default := "메모 관리"
A_TrayMenu.ClickCount := 2

^!n::MemoWindowManager.Open()

; Firestore host opens only desktopVisible=true memos. The manager stays hidden.
AppHost.Start()

HideAllMemos(*) {
    AppHost.HideAllVisible()
    MemoWindowManager.CloseAll()
}

LoadAppConfig() {
    global AppConfig
    path := A_ScriptDir "\config.json"
    if !FileExist(path) {
        AppConfig := Map("desktopLayer", false, "defaultWidth", 300, "defaultHeight", 320, "restoreOpenWindows", false)
        return
    }
    try {
        AppConfig := JSON.parse(FileRead(path, "UTF-8"), , true)
    } catch {
        AppConfig := Map("desktopLayer", false, "defaultWidth", 300, "defaultHeight", 320, "restoreOpenWindows", false)
    }
}

TestDesktopLayer() {
    result := DesktopLayer.SelfTest()
    MsgBox(result "`n`nWin+D 후에도 메모가 보이면 성공입니다.", "Desktop Layer", "Iconi")
}

OnExit(*) {
    ShowDesktopOverride.Stop()
    WindowStateStore.Save()
}
