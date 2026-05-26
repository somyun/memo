#Requires AutoHotkey v2.0
#Include "..\lib\DesktopLayer.ahk"
DesktopLayer.Reset()
try {
    w := DesktopLayer.Init()
    MsgBox DesktopLayer.SelfTest(), "Layer Init", "Iconi"
} catch as e {
    MsgBox e.Message, "Layer Init FAIL", "Icon!"
}
ExitApp()
