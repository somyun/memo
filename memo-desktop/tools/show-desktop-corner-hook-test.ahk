#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

g_orderText := 0
g_hideMinimizedCheck := 0

; ============================================================
; 설정값
; ============================================================
CORNER_BTN_WIDTH := 12   ; 코너 "바탕화면 보기" 버튼 가로 폭(px). 환경에 맞춰 조정.

; ============================================================
; 전역 상태
; ============================================================
g_isDesktopShown := false   ; 지금 우리가 만든 "바탕보기" 상태인지
g_touchedWindows := []      ; 우리가 실제로 최소화시킨 창들 (복원 대상)
g_orderSnapshot := []       ; 토글 시작 시점의 전체 Z-order 스냅샷 (테스트앱 포함, 복원 후 순서 재조립용)
g_busy := false             ; 토글 함수 재진입 방지
g_testGuiHwnd := 0          ; 아래에서 만들 테스트창의 핸들 (최소화 대상에서만 제외, 추적은 같이 함)

; ============================================================
; 0) 테스트용 GUI - "이 앱" 역할을 하는 실제로 보이는 창
;    조건 1~5를 눈으로 확인하려면 화면에 진짜 창이 떠 있어야 합니다.
;    특별한 always-on-top 스타일을 일부러 안 줬습니다 — 평범한 창이어야
;    조건 2/3(데스크톱보다 위, 일반 MRU 순서 참여)이 트릭 없이 공짜로 만족됩니다.
; ============================================================
TestGui := Gui("+Resize", "TestApp - 항상위 테스트")
TestGui.SetFont("s9", "Consolas")
TestGui.BackColor := "2244AA"
g_hideMinimizedCheck := TestGui.Add("CheckBox", "cWhite w380 Checked", "Hide minimized windows")
g_hideMinimizedCheck.OnEvent("Click", (*) => UpdateZOrderText())
g_orderText := TestGui.Add("Text", "cWhite w380 h260",
    "`n이 창이 테스트 대상 '앱'입니다.`n`n"
    . "1) 메모장/계산기 등을 열어서 Alt+Tab 순서를 만들어보세요`n"
    . "2) Win+D 또는 시계 옆 코너를 클릭해보세요`n"
    . "3) 다른 창은 사라지고 이 창만 남아야 정상입니다`n"
    . "4) 다시 누르면 Alt+Tab 순서가 원래대로 복귀해야 합니다")
TestGui.Show("w400 h300")
g_testGuiHwnd := TestGui.Hwnd
SetTimer(UpdateZOrderText, 250)
UpdateZOrderText()

; ============================================================
; 1) Win+D 가로채기
;    #d:: 정의만으로 AHK가 살아있는 동안 OS 기본 처리보다 우선합니다.
; ============================================================
#d:: ToggleShowDesktop()

; ============================================================
; 2) 코너 클릭("바탕화면 보기" 버튼) 가로채기 - 저수준 마우스 훅
;    검증된 방식(WH_MOUSE_LL=14)을 그대로 사용. "Fast" 옵션도 동일하게 유지.
; ============================================================
g_hookCb := CallbackCreate(MouseHookProc, "Fast", 3)
g_hook := DllCall("SetWindowsHookEx", "int", 14, "ptr", g_hookCb, "ptr", 0, "uint", 0, "ptr")

OnExit(ExitHandler)
ExitHandler(*) {
    global g_hook, g_hookCb
    DllCall("UnhookWindowsHookEx", "ptr", g_hook)
    CallbackFree(g_hookCb)
}

MouseHookProc(nCode, wParam, lParam) {
    global g_hook
    ; 0x201 = WM_LBUTTONDOWN, 0x202 = WM_LBUTTONUP
    if (nCode >= 0 && (wParam = 0x201 || wParam = 0x202)) {
        x := NumGet(lParam, 0, "Int")
        y := NumGet(lParam, 4, "Int")
        if InShowDesktopZone(x, y) {
            ; 클릭이 완료되는 시점(업)에만 실제 토글을 실행.
            ; 훅 콜백 자체는 빨리 리턴해야 하므로 무거운 작업은 타이머로 다음 틱에 넘김.
            if (wParam = 0x202)
                SetTimer(ToggleShowDesktop, -1)
            return 1   ; 메시지를 삼켜서 네이티브 바탕화면 보기 토글이 발동하지 않게 함
        }
    }
    return DllCall("CallNextHookEx", "ptr", g_hook, "int", nCode, "ptr", wParam, "ptr", lParam, "ptr")
}

InShowDesktopZone(x, y) {
    for hwnd in WinGetList("ahk_class Shell_TrayWnd") {
        if InTrayButtonRect(hwnd, x, y)
            return true
    }
    ; 멀티 모니터에서 작업표시줄을 여러 화면에 띄운 경우용 (단일 모니터면 빈 목록이라 무시됨)
    for hwnd in WinGetList("ahk_class Shell_SecondaryTrayWnd") {
        if InTrayButtonRect(hwnd, x, y)
            return true
    }
    return false
}

InTrayButtonRect(hwnd, x, y) {
    global CORNER_BTN_WIDTH
    WinGetPos(&tx, &ty, &tw, &th, "ahk_id " hwnd)
    return x >= tx + tw - CORNER_BTN_WIDTH && x < tx + tw && y >= ty && y < ty + th
}

; ============================================================
; 3/4) 토글 본체
;    [수정] SW_MINIMIZE는 Z-order를 그대로 안 둡니다 - 최소화되는 순간
;    창이 z-order 하단 쪽으로 밀려납니다. 그래서 그냥 복원만 하면
;    원래 순서가 아니라 "민 순서에 의해 결정된" 엉뚱한 순서가 나옵니다.
;    해결책: 토글 시작 시점의 전체 순서를 스냅샷으로 찍어두고,
;    복원 후 SetWindowPos를 DeferWindowPos로 묶어서 한 번에 적용해
;    그 순서를 강제로 재조립합니다. 중간에 무슨 일이 있었든 결과는
;    항상 원래 순서로 맞춰지고, 한 번에 적용되니 깜빡임도 없습니다.
; ============================================================
ToggleShowDesktop(*) {
    global g_isDesktopShown, g_busy
    if g_busy
        return
    g_busy := true
    try {
        if g_isDesktopShown
            RestoreWindows()
        else
            MinimizeWindows()
    } finally {
        g_busy := false
    }
}

MinimizeWindows() {
    global g_isDesktopShown, g_touchedWindows, g_orderSnapshot, g_testGuiHwnd

    ; 토글 시작 시점의 전체 순서(테스트앱 포함)를 먼저 찍어둔다.
    g_orderSnapshot := GetTrackedWindows()
    g_touchedWindows := []

    for hwnd in g_orderSnapshot {
        if (hwnd = g_testGuiHwnd)
            continue                                      ; 이 앱은 최소화하지 않음 (추적만 함)
        if !DllCall("IsIconic", "ptr", hwnd) {            ; 이미 최소화돼 있던 창은 손대지 않음
            DllCall("ShowWindow", "ptr", hwnd, "int", 6)  ; SW_MINIMIZE
            g_touchedWindows.Push(hwnd)
        }
    }
    g_isDesktopShown := true
}

RestoreWindows() {
    global g_isDesktopShown, g_touchedWindows, g_orderSnapshot

    ; 1) 일단 전부 보이게 복원 - 이 단계에서 순서가 엉켜도 무관 (다음 단계에서 강제로 재조립함)
    for hwnd in g_touchedWindows {
        if DllCall("IsWindow", "ptr", hwnd)
            DllCall("ShowWindow", "ptr", hwnd, "int", 4)  ; SW_SHOWNOACTIVATE
    }

    ; 2) 캡처해둔 원래 순서대로 Z-order를 강제로 재조립.
    ;    DeferWindowPos로 묶어서 한 번에 적용 -> 화면 갱신이 한 번만 일어나 깜빡임 없음.
    valid := []
    for hwnd in g_orderSnapshot {
        if DllCall("IsWindow", "ptr", hwnd)
            valid.Push(hwnd)
    }
    if (valid.Length > 1) {
        SWP_NOSIZE := 0x0001
        SWP_NOMOVE := 0x0002
        SWP_NOACTIVATE := 0x0010
        hdwp := DllCall("BeginDeferWindowPos", "int", valid.Length, "ptr")
        loop (valid.Length - 1) {
            i := A_Index
            if !hdwp
                break
            hdwp := DllCall("DeferWindowPos", "ptr", hdwp,
                "ptr", valid[i + 1], "ptr", valid[i],
                "int", 0, "int", 0, "int", 0, "int", 0,
                "uint", SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE, "ptr")
        }
        if hdwp
            DllCall("EndDeferWindowPos", "ptr", hdwp)
    }

    g_touchedWindows := []
    g_orderSnapshot := []
    g_isDesktopShown := false
}

UpdateZOrderText(*) {
    global g_orderText, g_hideMinimizedCheck, g_isDesktopShown, g_touchedWindows, g_busy, g_testGuiHwnd

    if !g_orderText || g_busy
        return

    try windows := GetTrackedWindows()
    catch as e {
        g_orderText.Text := "Z-order read failed:`n" e.Message
        return
    }

    foreground := DllCall("GetForegroundWindow", "ptr")
    hideMinimized := g_hideMinimizedCheck && g_hideMinimizedCheck.Value
    text := "Live Z-order, top -> bottom`n"
        . "State: " (g_isDesktopShown ? "desktop shown" : "normal")
        . " | touched: " g_touchedWindows.Length
        . " | minimized: " (hideMinimized ? "hidden" : "shown") "`n`n"

    shown := 0
    for index, hwnd in windows {
        isMin := DllCall("IsIconic", "ptr", hwnd)
        if hideMinimized && isMin
            continue

        shown += 1
        if (shown > 18)
            break

        number := Format("{:02}", shown)
        marker := hwnd = foreground ? "*" : " "
        self := hwnd = g_testGuiHwnd ? " [TEST]" : ""
        minText := isMin ? " [MIN]" : ""
        text .= number ". " marker " " SafeWinClass(hwnd) self minText " | " SafeWinTitle(hwnd) "`n"
    }

    g_orderText.Text := text
}

SafeWinTitle(hwnd) {
    try title := WinGetTitle("ahk_id " hwnd)
    catch
        return "<gone>"
    return title = "" ? "<no title>" : title
}

SafeWinClass(hwnd) {
    try cls := WinGetClass("ahk_id " hwnd)
    catch
        return "<gone>"
    return cls = "" ? "<no class>" : cls
}

FormatHwnd(hwnd) {
    return hwnd ? "0x" Format("{:X}", hwnd) : "0x0"
}

; ============================================================
; 윈도우 열거 + Alt-Tab류 필터
;    표준적인 "진짜 Alt-Tab 대상 창" 판별 기준을 그대로 적용합니다.
;    [수정] 테스트 GUI도 여기 포함시킵니다 - Z-order 재조립 시 같이
;    추적해야 하기 때문입니다 (최소화 제외는 MinimizeWindows에서 처리).
; ============================================================
g_enumResult := []

GetTrackedWindows() {
    global g_enumResult
    g_enumResult := []
    cb := CallbackCreate(EnumWindowsProc, "", 2)   ; 시간 제약 없는 일반 콜백 (Fast 아님)
    DllCall("EnumWindows", "ptr", cb, "ptr", 0)
    CallbackFree(cb)
    return g_enumResult
}

EnumWindowsProc(hwnd, lParam) {
    global g_enumResult
    try {
        if DllCall("IsWindow", "ptr", hwnd) && IsTrackedWindow(hwnd)
            g_enumResult.Push(hwnd)
    }
    return true   ; 1을 반환해야 열거가 계속됨
}

IsTrackedWindow(hwnd) {
    static GWL_EXSTYLE := -20
    static WS_EX_TOOLWINDOW := 0x80
    static WS_EX_APPWINDOW := 0x40000
    static GW_OWNER := 4
    static DWMWA_CLOAKED := 14

    ; 0) 이 스크립트의 숨겨진 메인 창만 제외 (테스트 GUI는 일부러 안 뺌 - 같이 추적해야 함)
    if (hwnd = A_ScriptHwnd)
        return false

    ; 1) 화면에 실제로 보이는 창만
    if !DllCall("IsWindowVisible", "ptr", hwnd)
        return false

    ; 2) DWM에 의해 cloak된 창 제외 (서스펜드된 UWP 등 - 실제로는 안 보이는 창)
    cloaked := Buffer(4, 0)
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "int", DWMWA_CLOAKED, "ptr", cloaked.Ptr, "uint", 4)
    if NumGet(cloaked, 0, "UInt") != 0
        return false

    ; 3) 셸/데스크톱 관련 창은 절대 건드리지 않음 (방어적 차단)
    cls := WinGetClass("ahk_id " hwnd)
    if (cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd" || cls = "Progman" || cls = "WorkerW")
        return false

    exStyle := DllCall("GetWindowLong", "ptr", hwnd, "int", GWL_EXSTYLE, "int")

    ; 4) Owner가 있는 창은 보통 Alt-Tab 대상이 아님 (WS_EX_APPWINDOW로 강제된 경우는 포함)
    owner := DllCall("GetWindow", "ptr", hwnd, "uint", GW_OWNER, "ptr")
    if (owner && !(exStyle & WS_EX_APPWINDOW))
        return false

    ; 5) 툴윈도우는 보통 Alt-Tab 대상이 아님 (WS_EX_APPWINDOW로 강제된 경우는 포함)
    if (exStyle & WS_EX_TOOLWINDOW) && !(exStyle & WS_EX_APPWINDOW)
        return false

    ; 6) 제목 없는 창은 대부분 헬퍼/배경 창
    if DllCall("GetWindowTextLength", "ptr", hwnd, "int") = 0
        return false

    return true
}

; ============================================================
; 트레이 메뉴 - 테스트/복구용 보조 기능
; ============================================================
A_TrayMenu.Insert("1&", "토글 수동 실행 (테스트)", (*) => ToggleShowDesktop())
A_TrayMenu.Insert("2&", "강제로 전부 복원 (안전장치)", (*) => RestoreWindows())
A_TrayMenu.Insert("3&")   ; 구분선
