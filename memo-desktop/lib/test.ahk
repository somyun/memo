#Requires AutoHotkey v2.0

#Include DesktopLayer.ahk

result := DesktopLayer.Init()

if !result {
    MsgBox "DesktopLayer 초기화 실패"
    ExitApp
}


MsgBox "
(
DesktopLayer 초기화 성공

테스트 방법:

1. 창이 바탕화면에 붙는지 확인
2. Win+D 눌러보기
3. 일반 창(크롬 등)을 띄워보기

원하는 동작:

* 바탕화면에서는 메모가 보임
* 일반 창은 메모 위에 올라옴
  )"

; =========================
; 테스트 GUI 생성
; =========================

gui1 := Gui("+Resize -Caption +ToolWindow")
gui1.BackColor := "FFF59D"

gui1.AddEdit(
    "x10 y10 w280 h180",
    "DesktopLayer 테스트"
)

txt := gui1.AddEdit(
"x10 y10 w280 h180",
"DesktopLayer 테스트`n`nWin+D를 눌러보세요."
)

btnDetach := gui1.AddButton(
"x10 y200 w130 h35",
"Detach"
)

btnAttach := gui1.AddButton(
"x160 y200 w130 h35",
"Attach"
)

gui1.Show("x100 y100 w300 h250")

Sleep 1000

DesktopLayer.Attach(gui1.Hwnd)
WinGetPos(&x2, &y2, &w2, &h2, gui1)

MsgBox "After Attach x: " x2 " y: " y2 " w: " w2 " h: " h2

parent := DllCall(
    "GetParent",
    "ptr", gui1.Hwnd,
    "ptr"
)

MsgBox "Parent HWND: " parent " vs " DesktopLayer.workerHwnd

; =========================
; 버튼 이벤트
; =========================

btnDetach.OnEvent("Click", (*) => DetachWindow())

btnAttach.OnEvent("Click", (*) => AttachWindow())

DetachWindow() {
	global gui1


	DesktopLayer.Detach(gui1.Hwnd)

	MsgBox "일반 창으로 복귀"

}

AttachWindow() {
	global gui1


	DesktopLayer.Attach(gui1.Hwnd)

	MsgBox "Desktop Layer로 다시 부착"


}

; =========================
; ESC 종료
; =========================

Esc::ExitApp
