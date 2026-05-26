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

global AppConfig := Map()

LoadAppConfig()
WindowStateStore.Load()
DesktopLayer.Reset()

; 트레이
A_IconTip := "Memo Desktop"
A_TrayMenu.Delete()
A_TrayMenu.Add("새 메모", (*) => MemoWindowManager.Open())
A_TrayMenu.Add("바탕화면 레이어 테스트", (*) => TestDesktopLayer())
A_TrayMenu.Add("모든 창 닫기", (*) => MemoWindowManager.CloseAll())
A_TrayMenu.Add("종료", (*) => ExitApp())
A_TrayMenu.Default := "새 메모"
A_TrayMenu.ClickCount := 1

^!n::MemoWindowManager.Open()

; 시작 시 복원 또는 빈 메모 1개
if (AppConfig.Has("restoreOpenWindows") && AppConfig["restoreOpenWindows"]) {
    ids := WindowStateStore.AllIds()
    if (ids.Length > 0) {
        for id in ids
            MemoWindowManager.Open(id, true)
    } else {
        MemoWindowManager.Open()
    }
} else {
    MemoWindowManager.Open()
}

LoadAppConfig() {
    global AppConfig
    path := A_ScriptDir "\config.json"
    if !FileExist(path) {
        AppConfig := Map("desktopLayer", true, "defaultWidth", 300, "defaultHeight", 320, "restoreOpenWindows", true)
        return
    }
    try {
        AppConfig := JSON.parse(FileRead(path, "UTF-8"), , true)
    } catch {
        AppConfig := Map("desktopLayer", true, "defaultWidth", 300, "defaultHeight", 320)
    }
}

TestDesktopLayer() {
    result := DesktopLayer.SelfTest()
    MsgBox(result "`n`nWin+D 후에도 메모가 보이면 성공입니다.", "Desktop Layer", "Iconi")
}

OnExit(*) {
    WindowStateStore.Save()
}
