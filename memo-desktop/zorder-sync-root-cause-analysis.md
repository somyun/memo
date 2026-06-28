# memo-desktop z-order sync issue analysis

## 요약

두 개 이상의 메모카드가 표시중일 때, 한 메모의 핀 고정 상태를 변경하거나 새 메모를 생성하면 다른 앱 뒤에 있던 나머지 메모카드들이 다른 앱 앞으로 올라오는 현상이 있다.

가장 유력한 원인은 Firestore 동기화 이벤트를 처리할 때 이미 열려 있는 메모카드까지 다시 `Show()`하고, 모든 표시중 메모에 `WinSetAlwaysOnTop()`을 재적용하는 구조다. 즉, 상태가 바뀐 메모만 갱신하는 reactive diff 방식이 아니라 표시중인 전체 메모 목록에 대해 창 제어 명령을 반복 실행하는 imperative replay 방식으로 동작하고 있다.

## 관찰된 증상

- 메모카드 A, B가 모두 표시중이다.
- B는 다른 앱 뒤에 가려져 있다.
- A에서 상단 고정 또는 고정 해제를 누른다.
- 또는 관리창에서 새 메모를 생성한다.
- 이때 B처럼 사용자가 직접 건드리지 않은 메모카드도 다른 앱 앞으로 올라온다.

기대 동작은 다음과 같다.

- 핀 토글은 해당 메모카드의 topmost 상태만 바꾼다.
- 새 메모 생성은 새 메모카드만 표시한다.
- 기존에 다른 앱 뒤에 있던 나머지 메모카드의 z-order는 그대로 유지한다.

## 관련 파일

- `memo-desktop/ui/app.js`
  - `togglePinned()`: 메모카드의 핀 상태를 Firestore에 저장한다.
  - `createMemo()`: `desktopVisible: true`인 새 메모 문서를 생성한다.
  - `mountHost().syncVisible()`: Firestore snapshot을 받아 표시중인 전체 메모 목록을 AHK로 보낸다.
- `memo-desktop/lib/Bridge.ahk`
  - `syncVisibleMemos` 이벤트를 `MemoWindowManager.SyncVisible()`로 전달한다.
- `memo-desktop/lib/MemoWindowManager.ahk`
  - `SyncVisible()`: 표시중인 전체 메모 목록을 순회한다.
  - `Open()`: 이미 열린 창에도 `win.gui.Show()`를 호출한다.
  - `ApplyPinnedZOrder()`: 고정된 메모들을 `WinMoveTop()`으로 다시 올린다.
- `memo-desktop/lib/MemoWindow.ahk`
  - `SetPinnedState()`: 상태가 같아도 매번 `WinSetAlwaysOnTop(1/0)`을 호출한다.

## 현재 동작 흐름

### 핀 토글

1. 사용자가 메모 A의 핀 버튼을 누른다.
2. `ui/app.js`의 `togglePinned()`가 Firestore 문서에 `desktopPinned`, `desktopPinnedAt`, `desktopUpdated`를 저장한다.
3. 숨겨진 host WebView가 Firestore snapshot 변경을 감지한다.
4. host의 `syncVisible()`은 변경된 메모 A만 보내지 않고, `desktopVisible === true`인 모든 메모를 `items`로 보낸다.
5. `Bridge.ahk`가 `syncVisibleMemos` 이벤트를 받아 `MemoWindowManager.SyncVisible(items)`를 호출한다.
6. `SyncVisible()`은 모든 item에 대해 `Open(id, true, false, "sync")`를 호출한다.
7. `Open()`은 이미 열린 메모창도 `win.gui.Show()`로 다시 표시한다.
8. 그 결과 다른 앱 뒤에 있던 기존 메모창들이 앞으로 올라올 수 있다.
9. 이어서 `SetPinnedState()`와 `ApplyPinnedZOrder()`도 실행되어 z-order가 추가로 흔들릴 수 있다.

### 새 메모 생성

1. 사용자가 관리창에서 새 메모를 만든다.
2. `createMemo()`가 `desktopVisible: true`인 새 Firestore 문서를 생성한다.
3. host snapshot이 다시 발생한다.
4. host는 새 메모만이 아니라 현재 표시중인 전체 메모 목록을 AHK로 보낸다.
5. `SyncVisible()`은 기존 메모들까지 다시 `Open()` 처리한다.
6. 이미 열린 기존 메모들에도 `win.gui.Show()`가 호출되어 다른 앱 앞으로 올라올 수 있다.

## 핵심 원인

### 1. 기존 창에도 `Show()`를 다시 호출함

`MemoWindowManager.Open()`은 이미 창이 있고 준비된 상태이면 다음처럼 동작한다.

```ahk
if this.windows.Has(memoId) {
    win := this.windows[memoId]
    if win.gui && win.ready {
        win.gui.Show()
        return memoId
    }
}
```

이 코드는 사용자가 명시적으로 메모를 다시 여는 상황에서는 자연스럽지만, Firestore sync 경로에서는 부작용이 크다. `Show()`는 단순 상태 확인이 아니라 Windows 창 관리자에게 해당 창을 다시 표시하라는 명령이다. 따라서 다른 앱 뒤에 있던 메모창의 z-order가 바뀔 수 있다.

문제의 핵심은 `source = "sync"`인 경우에도 사용자 액션과 같은 방식으로 기존 창을 다시 보여준다는 점이다.

### 2. 전체 snapshot을 명령 재실행으로 처리함

Vue 같은 reactive UI에서는 특정 상태가 바뀌면 해당 상태를 사용하는 부분만 갱신된다. 하지만 현재 AHK 창 관리자는 전체 표시중 목록을 받을 때마다 다음 작업을 반복한다.

- 목록의 모든 메모에 대해 `Open()` 호출
- 모든 표시중 메모에 대해 `SetPinnedState()` 호출
- 모든 pinned 메모에 대해 `ApplyPinnedZOrder()` 호출

따라서 실제 변경은 메모 A 하나에만 있어도 B, C의 창 상태까지 다시 건드린다.

### 3. `SetPinnedState()`가 idempotent하지 않음

`MemoWindow.SetPinnedState()`는 현재 상태와 새 상태가 같아도 매번 `WinSetAlwaysOnTop(1)` 또는 `WinSetAlwaysOnTop(0)`을 호출한다.

```ahk
if this.pinned
    WinSetAlwaysOnTop(1, "ahk_id " this.gui.Hwnd)
else
    WinSetAlwaysOnTop(0, "ahk_id " this.gui.Hwnd)
```

`WinSetAlwaysOnTop()` 역시 z-order에 영향을 줄 수 있는 Win32 명령이다. 특히 sync가 자주 발생하면 변경 없는 메모에도 topmost/notopmost 전환 명령이 반복 적용된다.

### 4. `ApplyPinnedZOrder()`가 모든 sync 후 실행됨

`SyncVisible()` 끝에서는 항상 `ApplyPinnedZOrder()`를 호출한다.

```ahk
this.ApplyPinnedZOrder()
```

이 함수는 pinned 메모를 정렬한 뒤 `WinMoveTop()`으로 순서대로 올린다. pinned 메모가 하나라도 있으면 Firestore snapshot마다 pinned 창을 다시 앞으로 올리는 효과가 생길 수 있다.

## 해결 방향

### 1차 수정: sync 경로에서는 기존 창을 다시 `Show()`하지 않기

가장 우선순위가 높은 수정이다. `source = "sync"`일 때 이미 열린 창은 존재 확인만 하고 z-order를 건드리지 않아야 한다.

예상 형태:

```ahk
if this.windows.Has(memoId) {
    win := this.windows[memoId]
    if win.gui && win.ready {
        if (source != "sync")
            win.gui.Show("NoActivate")
        return memoId
    }
}
```

더 보수적인 방향은 sync에서는 `Show()` 자체를 호출하지 않는 것이다. `Show("NoActivate")`도 z-order에 영향을 줄 수 있으므로, 기존 창을 그대로 두는 편이 더 안전하다.

의도:

- Firestore sync: 창이 없으면 만들고, 이미 있으면 건드리지 않는다.
- 사용자 직접 열기: 해당 창을 다시 보여주거나 앞으로 가져올 수 있다.

### 2차 수정: `SetPinnedState()`를 변경 발생 시에만 실행

현재 상태와 새 상태가 같으면 `WinSetAlwaysOnTop()`을 호출하지 않도록 한다.

예상 형태:

```ahk
SetPinnedState(pinned, pinnedAt := 0) {
    nextPinned := !!pinned
    nextPinnedAt := pinnedAt ? pinnedAt : 0

    if (this.pinned = nextPinned && this.pinnedAt = nextPinnedAt)
        return false

    this.pinned := nextPinned
    this.pinnedAt := nextPinnedAt

    if !this.gui
        return true

    if this.pinned
        WinSetAlwaysOnTop(1, "ahk_id " this.gui.Hwnd)
    else
        WinSetAlwaysOnTop(0, "ahk_id " this.gui.Hwnd)

    return true
}
```

주의할 점:

- 핀 해제 시에는 `WinSetAlwaysOnTop(0)`이 반드시 한 번 실행되어야 한다.
- 따라서 무조건 생략이 아니라, 상태가 실제로 바뀐 경우에만 실행해야 한다.

### 3차 수정: `ApplyPinnedZOrder()`를 필요한 경우에만 호출

모든 sync 후 무조건 pinned z-order를 재적용하지 말고, 다음 경우에만 호출하는 것이 좋다.

- 어떤 메모의 pinned 상태가 바뀐 경우
- 어떤 메모의 `pinnedAt`이 바뀐 경우
- 새로 열린 메모가 pinned 상태인 경우
- show-desktop 복구처럼 의도적으로 pinned 순서를 복원해야 하는 경우

예상 형태:

```ahk
pinChanged := false

for item in items {
    ...
    if this.windows.Has(id) {
        changed := win.SetPinnedState(pinned, pinnedAt)
        if changed
            pinChanged := true
    }
}

if pinChanged
    this.ApplyPinnedZOrder()
```

### 4차 수정: `SyncVisible()`를 diff 기반으로 정리

궁극적으로는 `SyncVisible()`이 전체 목록을 받아도 실제 동작은 차이만 반영해야 한다.

목표 동작:

- 목록에는 있고 창은 없음: 새 창 생성
- 목록에도 있고 창도 있음: 상태가 바뀐 경우만 반영
- 창은 있는데 목록에는 없음: 창 닫기
- 그 외: 아무 것도 하지 않음

개념 모델:

```text
Firestore 전체 snapshot
        ↓
현재 열린 창 목록과 비교
        ↓
새로 생긴 메모만 Open
사라진 메모만 Close
핀 상태가 바뀐 메모만 topmost 변경
나머지 메모는 z-order를 건드리지 않음
```

## 권장 적용 순서

1. `MemoWindowManager.Open()`에서 `source = "sync"`일 때 기존 창에 `Show()`를 호출하지 않도록 수정한다.
2. `MemoWindow.SetPinnedState()`가 실제 변경 여부를 반환하도록 만들고, 상태가 같으면 Win32 호출을 생략한다.
3. `MemoWindowManager.SyncVisible()`에서 pinned 관련 변경이 있을 때만 `ApplyPinnedZOrder()`를 호출한다.
4. 필요하면 사용자 액션용 open과 sync용 ensure-open을 함수 수준에서 분리한다.

## 검증 시나리오

### 시나리오 A: 핀 고정

1. 메모 A, B를 표시한다.
2. 다른 앱을 B 위에 올려 B를 가린다.
3. A의 핀 고정을 켠다.
4. 기대 결과:
   - A는 topmost로 올라온다.
   - B는 다른 앱 뒤에 그대로 있어야 한다.

### 시나리오 B: 핀 해제

1. A는 pinned, B는 unpinned 상태로 둔다.
2. 다른 앱을 B 위에 올려 B를 가린다.
3. A의 핀을 해제한다.
4. 기대 결과:
   - A는 topmost가 해제된다.
   - B는 앞으로 올라오지 않는다.

### 시나리오 C: 새 메모 생성

1. 메모 A, B를 표시한다.
2. 다른 앱을 A 또는 B 위에 올려 일부 메모를 가린다.
3. 관리창에서 새 메모 C를 생성한다.
4. 기대 결과:
   - C만 새로 표시된다.
   - A, B의 z-order는 유지된다.

### 시나리오 D: 일반 Firestore 변경

1. 메모 A, B를 표시한다.
2. 다른 앱을 B 위에 올려 B를 가린다.
3. A의 텍스트나 bounds 같은 비핀 상태를 변경한다.
4. 기대 결과:
   - B는 앞으로 올라오지 않는다.
   - pinned 상태가 바뀌지 않았다면 `ApplyPinnedZOrder()`가 실행되지 않는다.

## 결론

이번 현상은 Windows z-order 자체가 예측 불가능해서라기보다, 동기화 처리 코드가 표시중인 모든 메모에 창 표시 명령과 topmost 명령을 반복 적용하기 때문에 발생할 가능성이 높다.

해결의 핵심은 AHK 창 관리자를 전체 재실행 방식에서 diff 기반 방식으로 바꾸는 것이다. 즉, 이미 열린 창은 sync 중에 다시 보여주지 않고, pinned/topmost 관련 Win32 호출도 실제 상태가 바뀐 창에만 적용해야 한다.
