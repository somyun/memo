#Requires AutoHotkey v2.0
logPath := A_ScriptDir "\..\..\debug-013048.log"

Log(msg, data := "") {
    global logPath
    line := '{"sessionId":"013048","hypothesisId":"H4","location":"workerw-probe.ahk","message":"' msg '","data":' data ',"timestamp":' . A_TickCount . '}`n'
    FileAppend(line, logPath, "UTF-8")
}

progman := WinExist("ahk_class Progman")
shellW := DllCall("GetShellWindow", "ptr")
defOnProg := DllCall("FindWindowEx", "ptr", progman, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0, "ptr")
defOnShell := shellW ? DllCall("FindWindowEx", "ptr", shellW, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0, "ptr") : 0

workerCount := 0
for hwnd in WinGetList("ahk_class WorkerW")
    workerCount++

; Enum all top-level classes containing DefView
defHosts := []
for hwnd in WinGetList() {
    dv := DllCall("FindWindowEx", "ptr", hwnd, "ptr", 0, "str", "SHELLDLL_DefView", "ptr", 0, "ptr")
    if dv {
        cls := WinGetClass(hwnd)
        defHosts.Push(Map("hwnd", hwnd, "class", cls, "defView", dv))
    }
}

hostsJson := "["
first := true
for h in defHosts {
    if !first
        hostsJson .= ","
    first := false
    hostsJson .= '{"hwnd":' . h["hwnd"] . ',"class":"' . h["class"] . '","defView":' . h["defView"] . '}'
}
hostsJson .= "]"

Log("desktop probe", '{"progman":' . progman . ',"shellW":' . shellW . ',"defOnProg":' . defOnProg
    . ',"defOnShell":' . defOnShell . ',"workerCount":' . workerCount . ',"defHosts":' . hostsJson . ',"os":"' . A_OSVersion . '"}')

; try 0x052C variants
for _, params in [[0,0],[0,1],[0xD,0],[0xD,1]] {
    DllCall("SendMessageTimeout", "ptr", progman, "uint", 0x052C, "ptr", params[1], "ptr", params[2], "uint", 0, "uint", 1000, "ptr", 0)
    Sleep 100
    wc := 0
    for hwnd in WinGetList("ahk_class WorkerW")
        wc++
    Log("after 052C", '{"wParam":' . params[1] . ',"lParam":' . params[2] . ',"workerCount":' . wc . '}')
}

ExitApp()
