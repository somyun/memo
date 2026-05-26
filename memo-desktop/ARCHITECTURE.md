# Memo Desktop — 아키텍처

Windows 스티커 메모와 유사한 UX를 목표로 하는 **AHK v2(네이티브) + WebView2(Vue UI)** 하이브리드 데스크탑 앱입니다.

## 1. 레이어 구조

```
┌─────────────────────────────────────────────────────────┐
│  Vue 3 (UI/)          Firebase SDK, onSnapshot, 검색     │
│  bridge.js            WebView2 postMessage              │
└───────────────────────────┬─────────────────────────────┘
                            │ JSON (request/response/event)
┌───────────────────────────▼─────────────────────────────┐
│  AHK Main.ahk                                           │
│  ├─ MemoWindowManager   다중 창 생명주기                  │
│  ├─ MemoWindow          Gui + WebView2 Controller       │
│  ├─ Bridge              메시지 라우팅·상관 ID            │
│  ├─ DesktopLayer        WorkerW/Progman 부모 지정         │
│  ├─ WindowStateStore    창 위치·크기 JSON                 │
│  └─ Tray / Hotkeys      시스템 통합                       │
└───────────────────────────┬─────────────────────────────┘
                            │ Win32 API
┌───────────────────────────▼─────────────────────────────┐
│  Windows Shell (Progman → WorkerW → 메모 HWND)          │
│  일반 TOPMOST 앱 창 (Z-order 상위)                        │
└─────────────────────────────────────────────────────────┘
```

### 역할 분담

| 계층 | 담당 |
|------|------|
| **AHK** | 창 생성·파괴, WebView2 호스팅, 바탕화면 레이어, 트레이·단축키, 드래그·리사이즈, 창 상태 저장, 파일 다운로드·D&D(후속), 브리지 |
| **Vue** | 스티커 UI, Firestore 읽기/쓰기, debounce 자동저장, 검색 UI(후속), 첨부 UI(후속) |

AutoHotkey **GUI 컨트롤로 UI를 그리지 않습니다.** Gui는 WebView2를 담는 **호스트 창**만 제공합니다 (`통합자동화_v3\Main.ahk`와 동일 패턴).

---

## 2. 바탕화면 통합 (WorkerW / Progman)

### 왜 AlwaysOnTop이 아닌가

`HWND_TOPMOST`는 모든 일반 창 **위**에 고정됩니다. 목표는:

```
바탕화면(배경·아이콘)
  ↑ 메모 창들
  ↑ 일반 앱 (Word, 브라우저 등)
```

즉 메모는 **바탕화면 바로 위**, 일반 앱은 **메모 위** — Win+D로 바탕화면을 볼 때도 메모는 남아야 합니다.

### Windows 데스크탑 창 계층 (개념)

| 창 | 클래스 | 역할 |
|----|--------|------|
| **Progman** | `Progman` | 전통적인 Program Manager / 데스크탑 루트 |
| **WorkerW** | `WorkerW` | Vista 이후 Shell이 만드는 보조 레이어 (배경 등) |
| **SHELLDLL_DefView** | (Progman 또는 WorkerW 자식) | 바탕화면 **아이콘** 영역 |
| **SysListView32** | DefView 자식 | 실제 아이콘 리스트 |

Win10 1607+ 이후 Explorer는 `WM_SPAWN_WORKER` (`0x052C`)로 **아이콘 뒤**에 빈 `WorkerW`를 하나 더 둡니다.  
Rainmeter·데스크탑 위젯 계열이 쓰는 방식과 동일합니다 (`ImagePut.ahk` `BitmapToDesktop` 참고).

### 구현 절차 (`lib/DesktopLayer.ahk`)

1. `Progman`에 `SendMessage(0x052C, …)` — WorkerW 생성 유도  
2. `SHELLDLL_DefView`를 자식으로 가진 `WorkerW` 탐색  
3. 그 HWND **다음** 형제 `WorkerW` = 아이콘 **뒤** 레이어  
4. 메모 Gui HWND에 `SetParent(targetWorkerW)` + `WS_CHILD`  
5. 작업 표시줄 숨김: `WS_EX_TOOLWINDOW` (자식+툴윈도우 조합)

이렇게 붙인 창은 **데스크탑 셸의 일부**로 취급되어 Win+D 시에도 숨지지 않고, 일반 **top-level** 앱은 여전히 위에 그려집니다.

### 리스크·테스트

- Windows 11 24H2+, 다중 모니터, 가상 데스크탑에서 WorkerW 구조가 달라질 수 있음 → `DesktopLayer.selfTest`로 부모·가시성 로그  
- `SetParent` 후 좌표는 **부모 클라이언트** 기준 → `WindowStateStore`는 화면 좌표 저장 후 attach 시 변환  
- DWM 그림자: 자식 창에서는 `-Caption +Resize` + `DwmExtendFrameIntoClientArea` 유지 (`Main.ahk`와 동일)

---

## 3. WebView2 호스팅

### 환경 공유

- 앱당 **WebView2 Environment 1개** (`userDataFolder`: `%LocalAppData%\MemoDesktop\WebView2`)  
- 메모창마다 **Controller 1개** (Gui HWND에 바인딩)  
- Electron 대비 프로세스·메모리 부담 감소

### 창 스타일 (메모 1개 = 창 1개)

```
Gui("-Caption +Resize +MinSize250x180", …)
→ WebView2.create(gui.Hwnd, …, sharedEnvironment)
→ Navigate file:///…/ui/index.html#<memoId>)
→ DesktopLayer.attach(gui.Hwnd)   ; MVP: 설정으로 on/off
```

### 로컬 UI 로드

`통합자동화_v3`와 동일: `file:///` URI, `AreDefaultContextMenusEnabled := false`, `wv.add_WebMessageReceived`.

개발 시 Vite dev server URL로 바꿀 수 있도록 `config.json`의 `uiMode` 확장 예정.

---

## 4. AHK ↔ JS 브리지

### 메시지 형식

```jsonc
// JS → AHK (request)
{ "id": "a1b2", "kind": "request", "method": "dragWindow", "params": {} }

// JS → AHK (event, 응답 없음)
{ "kind": "event", "method": "ready", "params": { "memoId": "abc" } }

// AHK → JS (response)
{ "id": "a1b2", "kind": "response", "ok": true, "result": {} }

// AHK → JS (push event)
{ "kind": "event", "method": "windowBounds", "params": { "x": 100, "y": 200, "w": 320, "h": 280 } }
```

### 메서드 (MVP)

| method | 방향 | 설명 |
|--------|------|------|
| `ready` | JS→AHK | WebView 로드 완료, memoId·초기 bounds 수신 |
| `dragWindow` | JS→AHK | 타이틀바 드래그 (`ReleaseCapture` + `WM_NCLBUTTONDOWN`) |
| `closeWindow` | JS→AHK | 창 닫기(상태 저장 후 destroy) |
| `deleteMemo` | JS→AHK | Firestore 삭제는 JS, 창만 닫을 때 호출 |
| `windowBounds` | AHK→JS | 이동·리사이즈 시 화면 좌표 전달 |
| `hostConfig` | AHK→JS | `desktopLayer`, `dataDir` 등 |

`lib/Bridge.ahk`에서 `method`별 디스패치, `id`로 `request`/`response` 상관.

---

## 5. Firebase / Firestore

### 기존 스키마 (memo-web · Android 공통)

컬렉션 `memos/{id}`:

- `text`, `images[]`, `files[{name,url}]`, `pinned`, `created`, `updated`

### onSnapshot (개념)

`onSnapshot`은 Firestore가 **서버·로컬 캐시 변경**을 push하는 리스너입니다.

- 첫 콜백: 현재 문서(또는 쿼리) 스냅샷  
- 이후: 다른 기기·콘솔에서 수정 시 **즉시** 재호출  
- 오프라인 시 로컬 캐시 먼저, 재연결 시 동기화  

데스크탑 MVP: **창 1개 = 문서 1개** → `doc(memoId).onSnapshot` (컬렉션 전체 리스너보다 가벼움).

검색·목록 창(후속): `collection("memos").onSnapshot` + Vue `computed` 필터.

### 첨부 (후속)

- 현재: GitHub API + jsDelivr (`memo-web`, `GitHubUploader.kt`)  
- 목표: Firebase Storage + Rules; 마이그레이션 시 `files[].url` 점진 변환

---

## 6. 폴더 구조

```
memo-desktop/
├── Main.ahk                 # 진입점, 트레이, 단축키
├── config.json              # desktopLayer, 기본 창 크기
├── ARCHITECTURE.md
├── lib/
│   ├── WebView2.ahk         # thqby (통합자동화_v3와 동일)
│   ├── JSON.ahk
│   ├── 64bit/WebView2Loader.dll
│   ├── Bridge.ahk
│   ├── DesktopLayer.ahk
│   ├── MemoWindow.ahk
│   ├── MemoWindowManager.ahk
│   └── WindowStateStore.ahk
├── ui/
│   ├── index.html
│   ├── style.css
│   ├── bridge.js
│   ├── app.js               # Vue 3
│   └── lib/vue.global.prod.js
└── data/
    └── windows.json           # { memoId: {x,y,w,h}, … }
```

---

## 7. MVP vs 이후

| MVP (1차) | 이후 |
|-----------|------|
| WebView2 + Vue 단일 메모창 | 다중창 풀·환경 재사용 최적화 |
| Firestore doc onSnapshot | 검색 패널, collection 리스너 |
| 생성·삭제·자동저장 | 첨부 D&D, AHK 다운로드 |
| windows.json 위치 저장 | `%AppData%` + 다중 모니터 |
| DesktopLayer attach + selfTest | Win11 빌드별 폴백 |
| 트레이·Ctrl+Alt+N | 전역 검색, Storage 마이그레이션 |

---

## 8. 실행

1. AutoHotkey v2 설치  
2. `lib\64bit\WebView2Loader.dll` 존재 확인 (통합자동화_v3에서 복사)  
3. Edge WebView2 Runtime 설치  
4. `Main.ahk` 실행  
5. 트레이 · **Ctrl+Alt+N** 새 메모  

`config.json`에서 `"desktopLayer": false`면 일반 top-level 창으로 UI·Firebase만 먼저 검증 가능합니다.
