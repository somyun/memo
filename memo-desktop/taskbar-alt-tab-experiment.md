# memo-desktop 작업표시줄/Alt+Tab 실험 기록

작성일: 2026-06-28

## 목적

메모 카드(`MemoWindow`)를 작업표시줄에서는 숨기되 Alt+Tab에는 남기고, 동시에 다음 기존 동작을 유지할 수 있는지 검토했다.

- 메모 카드끼리 top-level 창처럼 독립적인 z-order를 가진다.
- `메모1 > 탐색기 > 메모2` 같은 배치가 가능하다.
- 한 메모만 pin 했을 때 다른 메모가 topmost가 되거나 같이 움직이지 않는다.
- `desktopLayer:false` 상태의 일반 top-level 창 모델을 유지한다.

## 실험 1: 공유 owner (`+Owner`)

적용 형태:

```ahk
this.gui := Gui("-Caption +Resize +MinSize250x160 +Owner", "Memo " this.id)
```

검증 결과:

- 메모 카드들은 작업표시줄에 나오지 않았다.
- 메모 카드들은 Alt+Tab에 나왔다.
- 메모 여러 개가 Alt+Tab에 각각 나왔다.

문제점:

- 메모 여러 개의 z-order가 하나로 묶였다.
- `메모1 > 탐색기 > 메모2` 같은 배치가 되지 않았다.
- 메모1만 pin 해도 나머지 메모들도 같이 pin 된 것처럼 일반 앱 위로 올라왔다.
- 메모1의 pin을 끄고 메모2의 pin을 켜면, 메모2의 pin 효과가 무력화되는 현상이 있었다.

판단:

`+Owner`를 owner HWND 없이 사용하면 AHK의 기본 owner인 `A_ScriptHwnd` 아래에 모든 메모가 들어가며, 같은 owner 그룹으로 취급되는 것으로 보인다. 작업표시줄/Alt+Tab 조건은 좋아졌지만, z-order와 topmost 독립성이 깨져서 채택하기 어렵다.

## 실험 2: 메모별 숨은 owner

적용 형태:

```ahk
this.ownerGui := Gui("-Caption +ToolWindow", "Memo Owner " this.id)
this.ownerGui.Show("Hide x-32000 y-32000 w1 h1 NoActivate")
this.gui := Gui("-Caption +Resize +MinSize250x160 +Owner" this.ownerGui.Hwnd, "Memo " this.id)
```

검증 결과:

- `메모1 > 탐색기 > 메모2` 같은 z-order 배치가 가능해졌다.
- 메모 카드들은 작업표시줄에 나오지 않았다.

문제점:

- 메모 카드들이 Alt+Tab 리스트에서 사라졌다.
- 메모1만 pin 했을 때 메모2가 같이 topmost가 되지는 않았지만, 탐색기 뒤에 있던 메모2가 메모1 바로 뒤로 이동했다.
- 메모2만 pin 했을 때도 메모1이 메모2 바로 뒤로 이동했다.
- pin 해제 시에도 다른 메모가 pin을 해제한 메모 주변으로 이동했다.

판단:

메모별 owner를 분리하면 공유 owner보다 z-order 독립성은 개선되지만, Alt+Tab 노출 요구를 깨뜨린다. 또한 owned window 관계 자체가 pin/unpin 시 owner-chain z-order를 계속 건드리는 것으로 보인다. 이 방식도 채택하기 어렵다.

## 현재 기본 코드 상태

기본 실행 경로에서는 owner 계열 실험 코드를 사용하지 않는다.

`MemoWindow`는 owner 없는 일반 top-level 창으로 생성된다.

```ahk
this.gui := Gui("-Caption +Resize +MinSize250x160", "Memo " this.id)
```

실패한 owner/TaskbarList 실험 코드는 현재 작업트리에 남기지 않는다.

## 다음 후보: ITaskbarList::DeleteTab

owner 방식 대신, 메모 카드는 owner 없는 top-level 창으로 유지하고 Shell의 `ITaskbarList::DeleteTab(hwnd)`만 호출해서 작업표시줄 항목을 제거하는 방안을 검토한다.

Microsoft 문서 기준:

- `ITaskbarList`는 작업표시줄 항목을 동적으로 추가, 제거, 활성화하는 Shell 제공 COM 인터페이스다.
- `HrInit()`은 다른 `ITaskbarList` 메서드 호출 전에 먼저 호출해야 한다.
- `DeleteTab(hwnd)`는 지정한 HWND의 항목을 작업표시줄에서 제거한다.

기대 효과:

- owner를 부여하지 않으므로 메모 카드들은 계속 독립적인 top-level 창으로 남는다.
- `WS_EX_TOOLWINDOW`를 쓰지 않으므로 Alt+Tab까지 숨기는 부작용을 피할 가능성이 높다.
- `SetParent`/`desktopLayer`를 쓰지 않으므로 `WS_CHILD` 전환에 따른 pin 무력화 문제를 만들지 않는다.
- 작업표시줄 버튼 제거만 Shell에 요청하므로 z-order와 topmost는 기존 로직을 그대로 유지할 수 있다.

구현 방향 초안:

1. `MemoWindow` 생성 옵션은 owner 없는 현재 형태를 유지한다.
2. 메모 창이 실제로 표시된 뒤, 예를 들어 `Reveal()` 이후 `DeleteTab(this.gui.Hwnd)`를 호출한다.
3. Shell이 작업표시줄 버튼을 늦게 만들거나 다시 등록할 수 있으므로, 최초 호출 직후 짧은 지연 재호출을 1회 정도 검토한다.
4. `Show`, `Restore`, pin/unpin이 작업표시줄 항목을 다시 만들지 않는지 실측한다.
5. 실패 시에는 작업표시줄에 남는 기존 동작으로 폴백하고, Alt+Tab/z-order/topmost는 절대 건드리지 않는다.

AHK v2 구현 후보 형태:

```ahk
; CLSID_TaskbarList  = {56FDF344-FD6D-11d0-958A-006097C9A090}
; IID_ITaskbarList   = {56FDF342-FD6D-11d0-958A-006097C9A090}
; vtable index:
;   3 = HrInit
;   5 = DeleteTab

taskbar := ComObject("{56FDF344-FD6D-11d0-958A-006097C9A090}", "{56FDF342-FD6D-11d0-958A-006097C9A090}")
ComCall(3, taskbar)                  ; HrInit()
ComCall(5, taskbar, "ptr", hwnd)     ; DeleteTab(hwnd)
```

주의:

- `ITaskbarList`는 `IDispatch` 기반 Automation 객체가 아니므로 AHK v2에서 `ComCall` 기반 호출 검증이 필요하다.
- `DeleteTab`은 창 자체를 숨기는 API가 아니라 작업표시줄 항목만 제거하는 API다. 따라서 Alt+Tab 유지 여부는 실제 Windows 환경에서 검증해야 한다.
- 메모마다 매번 COM 객체를 만들기보다 `TaskbarList` 헬퍼 클래스로 한 번 초기화해 재사용하는 편이 낫다.

## 적용 1: TaskbarList 헬퍼

2026-06-29에 `ITaskbarList::DeleteTab(hwnd)` 방식의 1차 구현을 적용했다.

변경 사항:

- `lib/TaskbarList.ahk` 추가
- `Main.ahk`에서 `TaskbarList.ahk` include
- `MemoWindow.Show()`에서 offscreen 초기 표시 직후 `DeleteTab(hwnd)` 호출
- `MemoWindow.Reveal()`에서 실제 표시 직후 `DeleteTab(hwnd)` 재호출
- `MemoWindow.SetPinnedState()`에서 pin/topmost 변경 직후 `DeleteTab(hwnd)` 재호출
- Shell이 작업표시줄 버튼을 늦게 등록하는 경우를 대비해 250ms/500ms 지연 재호출 추가

현재 구현 의도:

- `MemoWindow`는 owner 없는 일반 top-level 창 생성 방식을 유지한다.
- `+Owner`, `+ToolWindow`, `WS_CHILD`, `SetParent`를 사용하지 않는다.
- 작업표시줄 버튼 제거만 Shell API에 맡긴다.
- Alt+Tab, z-order, pin/topmost 독립성은 기존 top-level 창 동작에 맡긴다.

검증할 항목:

- 메모 카드가 작업표시줄에서 사라지는지
- 메모 카드가 Alt+Tab에는 남는지
- 메모 여러 개가 Alt+Tab에 각각 나오는지
- `메모1 > 탐색기 > 메모2` 같은 z-order 배치가 유지되는지
- 메모1만 pin 했을 때 메모2가 같이 움직이거나 topmost가 되지 않는지
- pin 해제 시 다른 메모의 z-order가 같이 변하지 않는지

검증 결과:

- 작업표시줄 숨김: 성공
- Alt+Tab 유지: 실패
- 메모별 z-order 독립성: 성공
- pin 시 다른 메모가 딸려오지 않음: 성공

판단:

`ITaskbarList::DeleteTab(hwnd)` 단독 방식은 owner 계열보다 z-order와 pin 독립성은 좋지만, 현재 Windows 환경에서는 Alt+Tab 항목도 같이 제거되는 것으로 확인됐다. 따라서 "작업표시줄 숨김 + Alt+Tab 유지" 요구사항을 만족하지 못한다.

## 실험 3: 메모별 숨은 owner, owner에서 `+ToolWindow` 제거

2026-07-05에 실험 2에서 남아 있던 변수를 분리해 확인했다.

실험 2는 메모 창에 `+Owner`를 붙인 동시에, 숨은 owner 창을 다음처럼 `+ToolWindow`로 만들었다.

```ahk
this.ownerGui := Gui("-Caption +ToolWindow", "Memo Owner " this.id)
this.gui := Gui("-Caption +Resize +MinSize250x160 +Owner" this.ownerGui.Hwnd, "Memo " this.id)
```

따라서 Alt+Tab 실패 원인이 다음 둘 중 어느 쪽인지 아직 분리되지 않았다.

- owned window 관계 자체 때문에 Alt+Tab에서 빠진 것
- owner chain 어딘가에 `WS_EX_TOOLWINDOW`가 섞였기 때문에 Alt+Tab에서 빠진 것

이번 실험은 숨은 owner 창에서만 `+ToolWindow`를 제거했다.

```ahk
this.ownerGui := Gui("-Caption", "Memo Owner " this.id)
this.ownerGui.Show("Hide x-32000 y-32000 w1 h1 NoActivate")
this.gui := Gui("-Caption +Resize +MinSize250x160 +Owner" this.ownerGui.Hwnd, "Memo " this.id)
```

검증 결과:

- 작업표시줄 숨김: 실패
- 작업표시줄 hover 시 창 썸네일 미표시: 발생
- 메모 창은 작업표시줄에 여전히 표시됨

판단:

숨은 owner의 `+ToolWindow`를 제거해도 목표였던 작업표시줄 숨김은 달성되지 않았다. 달라진 것은 작업표시줄 hover 썸네일이 나오지 않는 정도였고, 작업표시줄 항목 자체는 남았다. 따라서 이 방식도 "작업표시줄 숨김 + Alt+Tab 유지" 요구사항을 만족하지 못한다.

## 실험 4: 숨은 owner + `DeleteTab` 병행

실험 3은 숨은 owner에서 `+ToolWindow`만 제거한 형태였고, 작업표시줄 항목 자체는 남았다. 실험 4는 같은 owner 구조에서 Shell의 `ITaskbarList::DeleteTab`을 함께 호출해, 작업표시줄 항목만 제거되면서 Alt+Tab 자격은 owner 관계 쪽에 남는지 확인한다.

적용 형태:

```ahk
this.ownerGui := Gui("-Caption", "Memo Owner " this.id)
this.ownerGui.Show("Hide x-32000 y-32000 w1 h1 NoActivate")
this.gui := Gui("-Caption +Resize +MinSize250x160 +Owner" this.ownerGui.Hwnd, "Memo " this.id)
TaskbarList.DeleteTab(this.ownerGui.Hwnd)
TaskbarList.DeleteTab(this.gui.Hwnd)
```

구현 메모:

- `lib/TaskbarList.ahk`를 다시 추가해 `ITaskbarList::DeleteTab(hwnd)`만 얇게 감싼다.
- `Main.ahk`에서 `TaskbarList.ahk`를 include한다.
- `MemoWindow`는 `taskbarAltTabExperiment = "ownerNoToolWindowDeleteTab"`일 때만 숨은 owner를 만든다.
- `Show`, `Reveal`, `SetPinnedState` 이후 `ownerGui.Hwnd`와 `gui.Hwnd` 양쪽에 `DeleteTab`을 호출한다.
- Shell의 지연 등록을 대비해 `Reveal` 이후 250ms/500ms 지연 재호출을 둔다.
- 숨은 owner는 `Close()`에서 메모 창과 함께 명시적으로 파괴한다.

검증할 항목:

- 메모 카드가 작업표시줄에서 사라지는지
- 메모 카드가 Alt+Tab에는 남는지
- 메모 여러 개가 Alt+Tab에 각각 나오는지
- `메모1 > 탐색기 > 메모2` 같은 z-order 배치가 유지되는지
- 한 메모만 pin 했을 때 다른 메모가 같이 움직이거나 topmost가 되지 않는지
- pin 해제 시 다른 메모의 z-order가 같이 변하지 않는지

검증 결과:

- 작업표시줄 숨김: 핵심 판단에서 제외. Alt+Tab/z-order 실패로 채택 불가.
- Alt+Tab 유지: 실패
- z-order 복구: 실패. 창 복구 시 이전 z-order가 완전하게 복구되지 않았다.

판단:

`DeleteTab`을 숨은 owner 구조와 병행해도 Alt+Tab 노출 요구를 만족하지 못했다. 또한 z-order 복구도 안정적이지 않아 기존 owner 계열 실험의 핵심 부작용이 남았다. 따라서 실험 4도 채택하지 않는다.

## 최종 방침

2026-07-05 기준으로 "작업표시줄 숨김 + Alt+Tab 유지 + z-order/pin 독립성"을 동시에 만족하는 Win32/AHK 조합을 찾지 못했다.

당분간 작업표시줄 숨김 요구는 포기하고, 다음 동작을 우선한다.

- 메모 카드는 owner 없는 일반 top-level 창으로 유지한다.
- Alt+Tab 노출은 유지한다.
- 메모별 z-order 독립성을 유지한다.
- pin/topmost 동작이 다른 메모를 끌고 오지 않게 한다.
- `desktopLayer:false` 상태의 안정적인 일반 창 모델을 유지한다.

따라서 현재 코드에서는 `+Owner`, `+ToolWindow`, `ITaskbarList::DeleteTab`, `SetParent`/`WS_CHILD` 방식 모두 사용하지 않는다.

## 참고 문서

- [Microsoft Learn - ITaskbarList interface](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-itaskbarlist)
- [Microsoft Learn - ITaskbarList::DeleteTab method](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-itaskbarlist-deletetab)
- [Microsoft Learn - The Taskbar](https://learn.microsoft.com/en-us/windows/win32/shell/taskbar)
- [AutoHotkey v2 - Gui Object](https://www.autohotkey.com/docs/v2/lib/Gui.htm)
