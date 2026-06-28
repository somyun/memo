# memo-desktop Z-order / 작업표시줄·Alt+Tab 분리 — 검증 요청 자료

> 다른 AI 에이전트의 추가 검증을 위해 작성된 문서입니다. 대화 맥락 없이도 이해할 수 있도록
> 저장소 정보, 관련 코드, 분석 내용을 모두 포함했습니다.

## 0. 프로젝트 컨텍스트

- 저장소: `github.com/somyun/memo` (공개 저장소), 분석 대상은 그 안의 `memo-desktop` 디렉토리
- 스택: **AHK v2(네이티브 호스트) + WebView2(렌더러) + Vue 3(UI) + Firebase Firestore(데이터/동기화)**
- 컨셉: Windows 스티커 메모와 유사한 데스크톱 위젯 앱. 메모마다 별도의 top-level 창(`MemoWindow`)을 띄우고, 모든 메모를 관리하는 별도 창(`ManagerWindow`)이 있음
- 핵심 설계 목표(기존 `ARCHITECTURE.md`에 명시): 전역 `AlwaysOnTop`을 쓰지 않고, **"바탕화면 < 메모카드 < 일반 앱"** 순서의 Z-계층을 만드는 것

### 메모카드 Z-위치를 결정하는 3단 구조 (기존 분석 결과, 전제 조건)

| 단계 | 담당 파일 | 메커니즘 |
|---|---|---|
| ① 기준선 | `lib/DesktopLayer.ahk` | `SetParent`로 메모 창을 `Progman`/`WorkerW`에 끼워 넣어 "바탕화면 위, 일반 앱 아래" 위치 확보. 단, `config.json`의 `desktopLayer`가 **현재 `false`**라 메모카드는 지금은 보통의 top-level(popup) 창으로 동작 중 |
| ② 개별 고정 | `lib/MemoWindow.ahk` `SetPinnedState()` | 사용자가 "상단 고정"을 누르면 `WinSetAlwaysOnTop`으로 `WS_EX_TOPMOST`를 켜서 ①의 기준선을 깨고 일반 앱보다도 위로 띄움 |
| ③ 고정 카드간 순서 | `lib/MemoWindowManager.ahk` `ApplyPinnedZOrder()` | 고정된 카드가 여럿이면 `pinnedAt`(고정 시각) 오름차순으로 정렬 후 `WinMoveTop`을 순서대로 호출 → 가장 최근에 고정한 카드가 맨 위로 옴 |

동기화 흐름: `Vue(app.js) togglePinned → Firestore desktopPinned/desktopPinnedAt → onSnapshot → syncVisibleMemos 이벤트 → Bridge.ahk → MemoWindowManager.SyncVisible → SetPinnedState + ApplyPinnedZOrder`

---

## 1. 잠재적 이슈 — 기존 3단 구조 분석에서 발견한 부분

### 이슈 1: `desktopLayer:true` 전환 시 ②(개별 고정)이 조용히 무력화될 위험

**현재 상태**: `config.json`에 `"desktopLayer": false`로 설정돼 있어, 메모카드는 지금 평범한 top-level 창이다. 이 상태에서는 `WS_EX_TOPMOST`(②의 핵심 메커니즘)가 정상적으로 작동해서, 고정된 메모카드가 일반 앱(Word, 브라우저 등)보다 위에 뜬다.

**문제 시나리오**: 나중에 `desktopLayer:true`로 전환하면, `DesktopLayer.Attach()`가 다음을 수행한다 (`lib/DesktopLayer.ahk:101-138`):

```ahk
style := (style & ~0x00C00000) | 0x40000000   ; WS_CHILD 부여
DllCall("SetParent", "ptr", hwnd, "ptr", parent)  ; WorkerW의 자식으로 편입
```

여기서 핵심 Win32 사실: **`WS_EX_TOPMOST`는 top-level(overlapped/popup) 창들 사이의 Z-band 개념이라, `WS_CHILD`가 된 창에는 의미가 없어진다.** Child 창의 Z-순서는 같은 부모 밑 형제(sibling)들 사이에서만 의미를 가지며, "다른 프로세스의 top-level 앱 위로 띄운다"는 효과는 더 이상 발생하지 않는다.

- `RaisePinned()`(`WinMoveTop`)는 child 모드에서도 동작은 한다 — 단, 그 효과가 "같은 WorkerW 밑의 다른 메모카드들 사이의 순서"로 의미가 축소된다.
- 즉 "고정 → 일반 앱보다 위" 라는 사용자에게 보여지는 기능이, desktopLayer 모드로 전환하는 순간 **코드 변경 없이도 조용히 깨질 수 있다.**

**검증 포인트**:
1. `WS_EX_TOPMOST`가 `WS_CHILD` 창에서 실제로 아무 효과가 없다는 게 맞는지 (Win32 공식 동작으로) 다시 확인해줄 것.
2. 만약 이게 맞다면, `desktopLayer:true` 모드에서 "고정 카드를 일반 앱 위로" 라는 요구사항을 만족시키려면 ②의 메커니즘 자체를 재설계해야 하는지(예: child 모드 포기하고 별도 top-level 오버레이 창을 만드는 방식 등) 의견을 구함.

### 이슈 2: `Reveal()` → `DesktopLayer.Attach()` 타이밍에 의한 일시적 z-order 흐트러짐 가능성

**관련 코드** (`lib/MemoWindow.ahk`):

```ahk
OnWebReady(params) {
    this.ready := true
    ...
    this.Reveal()   // 비동기 WebView2 ready 콜백 시점에 호출됨
    ...
}

Reveal() {
    if !this.gui || this.visible
        return
    this.gui.Show(this._showOptions " NoActivate")
    this.visible := true
    if this.useDesktopLayer {
        try DesktopLayer.Attach(this.gui.Hwnd, this._initialX, this._initialY, this._initialW, this._initialH)
        ...
    }
}
```

`DesktopLayer.Attach()` 내부 (`lib/DesktopLayer.ahk:121-122`):

```ahk
DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", cx, "int", cy, "int", screenW, "int", screenH
    , "uint", SWP_SHOWWINDOW)
```

여기서 `hwndInsertAfter` 파라미터로 넘어가는 `"ptr", 0`은 Win32 상수 `HWND_TOP`(=0)과 동일한 값이다. 즉 이 호출은 새로 부착된 창을 **그 시점 부모의 자식 z-순서 맨 위로** 올린다.

**문제 시나리오**: `MemoWindowManager.SyncVisible()`은 새 메모카드를 열 때(`Open()`) 곧바로 `SetPinnedState` + `ApplyPinnedZOrder()`를 호출해 고정 순서를 맞추는데, 이 시점에 해당 카드의 WebView2는 아직 화면 밖(`x-32000 y-32000`)에서 로딩 중일 수 있다. 이후 WebView2가 준비되면 비동기로 `OnWebReady → Reveal() → Attach()`가 실행되고, 위 `SetWindowPos(..., 0, ...)`가 **이미 적용해둔 고정 순서를 다시 흐트러뜨릴 수 있다** (desktopLayer 모드에서만 발생, 현재는 `desktopLayer:false`라 실제로는 발생하지 않음).

**검증 포인트**:
1. 이 타이밍 경쟁(race)이 실제로 재현 가능한 시나리오인지, 아니면 다음 `SyncVisible` 사이클(Firestore onSnapshot)에서 금방 다시 보정되어 사용자가 체감하기 어려운 수준인지 판단해줄 것.
2. 만약 실제 문제라면, `Attach()`에서 `hwndInsertAfter`를 `HWND_TOP` 대신 호출 시점의 정확한 형제 위치를 계산해서 넘기거나, `Attach()` 완료 후 `ApplyPinnedZOrder()`를 다시 한번 호출하는 식의 보정이 합리적인지 검토 요청.

---

## 2. 새 요구사항 검토 — "메모카드는 작업표시줄에서 숨기고 Alt+Tab에는 남기기"

### 요구사항

- 위 3단 Z-order 구조는 그대로 유지
- `ManagerWindow`(메모 관리자): 작업표시줄에 계속 표시
- `MemoWindow`(메모카드): 작업표시줄에는 안 보이되, **Alt+Tab 목록에는 나와야 함**

### 제시한 핵심 근거: 작업표시줄 노출과 Alt+Tab 노출은 같은 규칙이 아니다

| 처리 | 작업표시줄 | Alt+Tab |
|---|---|---|
| `WS_EX_TOOLWINDOW` 부여 | 숨김 | 숨김 |
| `Owner`만 부여 (TOOLWINDOW 없이) | 숨김 | **그대로 노출** |

- 이 저장소의 `lib/AppHost.ahk:24`는 이미 `Gui("-Caption +ToolWindow", "Memo Host")`를 사용 중인데, 이건 작업표시줄·Alt+Tab **둘 다**에서 사라져야 하는 순수 백그라운드 Firestore 리스너 호스트라서 맞는 선택.
- 이번 요구사항은 반대로 "작업표시줄만 숨김 + Alt+Tab 유지"이므로 `WS_EX_TOOLWINDOW`가 아니라 **`Owner`만 부여**하는 방식이 필요하다고 판단함.
- 근거: AHK v2 공식 문서(`Gui` 객체)는 `+Owner`를 "owner 지정 시 작업표시줄 버튼이 기본적으로 생기지 않는다"고 명시. 동시에 WPF(`dotnet/wpf#3623`)·Avalonia(`AvaloniaUI/Avalonia#16871`) 이슈 트래커에서 `ShowInTaskbar=false`(owner 기반 구현)만으로는 Alt+Tab에서 빠지지 않고, **Alt+Tab에서까지 빼려면 별도로 `ToolWindow` 스타일을 추가해야 한다**는 점이 명시적으로 언급됨 — 즉 "owner만 부여 → 작업표시줄만 숨김, Alt+Tab은 유지"는 실제로 검증된 동작.

### 제안한 구체적 변경

**`ManagerWindow`**: 변경 불필요. 현재 `Gui("+Resize +MinSize640x420", "Memo Manager")`로 owner 없는 평범한 top-level 창이라 작업표시줄·Alt+Tab 둘 다 자동 노출.

**`lib/MemoWindow.ahk` `Show()`**: Gui 생성 옵션에 `+Owner` 추가.

```ahk
// 변경 전
this.gui := Gui("-Caption +Resize +MinSize250x160", "Memo " this.id)

// 변경 후
this.gui := Gui("-Caption +Resize +MinSize250x160 +Owner", "Memo " this.id)
```

`+Owner`에 HWND를 안 주면 **스크립트의 항상-존재하는 메인 윈도우(`A_ScriptHwnd`)**가 자동으로 owner가 됨. 이 창은 프로세스 생명주기 내내 존재하고 절대 표시/최소화되지 않으므로 owner 관계가 끊어질 일이 없음.

### 기존 3단 구조와의 호환성 검토

- `WinSetAlwaysOnTop`(②), `ApplyPinnedZOrder`(③), `DesktopLayer.Attach`(① — 현재 off)는 전부 `GWL_HWNDPARENT`(owner) 필드를 참조하지 않으므로 `+Owner` 추가와 충돌하지 않는다고 판단.
- `ShowDesktopOverride.IsTrackedWindow`도 메모카드는 `IsProtectedWindow` OR 조건에서 먼저 걸러지므로 owner 유무와 무관하게 기존 로직 그대로 동작.
- **단, 위 "이슈 1"과 직접 연결되는 지점**: `desktopLayer:true`로 전환하면 `SetParent`(WS_CHILD)가 같은 `GWL_HWNDPARENT` 필드를 owner 용도가 아니라 진짜 parent 용도로 덮어써버린다. WS_CHILD가 된 창은 owner 여부와 무관하게 작업표시줄·Alt+Tab 양쪽 열거 대상에서 원천 제외되므로(top-level이 아니라서), 그 시점부터는 "Alt+Tab에는 보여야 한다"는 이번 요구사항이 다시 깨진다. 즉 desktopLayer 모드를 켜는 순간, **이슈 1(고정 기능 무력화)과 이번 요구사항(Alt+Tab 노출)이 동시에 같은 원인(`WS_CHILD` 전환)으로 깨지는 구조**라고 판단했음.

### 짚어둔 함정

- owner를 `ManagerWindow.gui.Hwnd`로 잡으면 안 됨 — Win32에서 owner 창을 최소화하면 그 owner가 가진 owned 창들도 함께 숨겨지는 게 표준 동작이라, 사용자가 메모 관리자 창을 최소화하는 순간 열려있는 메모카드 전체가 같이 사라지는 부작용이 생길 수 있음. `A_ScriptHwnd`(절대 안 보이고 안 건드리는 메인 윈도우) 사용을 권장함.

### 검증 요청 포인트 (이번 섹션)

1. **"`Owner`만 부여 시 작업표시줄만 숨겨지고 Alt+Tab은 유지된다"**는 핵심 주장 자체를 다시 검증해줄 것. (Windows 10/11 기준으로, 특히 최신 빌드의 Alt+Tab/Task Switcher가 구버전과 동일한 owner-chain 규칙을 따르는지)
2. `+Owner`로 `A_ScriptHwnd`를 owner로 쓰는 것이 AHK v2에서 실제로 의도대로 동작하는지(특히 WebView2를 호스팅하는 Gui 창에 적용했을 때 부작용 없는지) 확인 요청.
3. "owner 창이 최소화되면 owned 창도 같이 숨겨진다"는 부작용 설명이 정확한지, 그리고 이게 `A_ScriptHwnd`(보이지 않는 메인 윈도우)에는 해당하지 않는다는 결론이 맞는지 검증.
4. `desktopLayer:true` 전환 시 이슈 1과 이번 요구사항이 동시에 깨진다는 연결고리 분석이 타당한지, 그리고 그 경우의 대안(예: child 모드를 포기하고 별도 오버레이 방식, 또는 Alt+Tab 자체를 가로채는 커스텀 스위처 구현)에 대해 추가 의견이 있는지.
