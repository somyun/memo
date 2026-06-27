# AHK 단일 프로세스 정식앱 리팩토링 계획

## 목표

Memo Desktop 정식앱은 하나의 AutoHotkey 프로세스가 전체 데스크톱 런타임을 소유하는 구조로 전환한다.

이 프로세스가 담당하는 범위는 다음과 같다.

- 시스템 트레이 아이콘과 트레이 메뉴
- 여러 개의 스티커 메모카드 창
- 일반 Windows 형태의 메모 관리창
- WebView2 기반 카드/관리 UI
- Firebase Firestore 동기화
- Win+D 및 작업표시줄 우측 바탕화면 보기 버튼 오버라이드

기존 WinForms 구현은 공식 런타임에서 제외한다. Windows 키 시퀀스를 C# 저수준 훅으로 안정적으로 처리하기 어렵고, 검증된 AHK `#d` 핫키 방식이 현재 목표에는 더 안전하다.

## 핵심 방향

- C# 앱과 AHK 보조 프로세스를 동시에 실행하지 않는다.
- 보호 대상 창 판별, 바탕화면 보기 오버라이드, WebView2 UI 호스팅을 모두 같은 AHK 프로세스 안에서 처리한다.
- UI는 네이티브 AHK 컨트롤이 아니라 WebView2와 CSS로 구현한다.
- 기존 웹/안드 앱과 같은 Firestore `memos/{id}` 컬렉션을 계속 사용한다.
- 데스크톱 전용 필드는 선택 필드로 추가하고, 웹/안드와의 기존 호환성을 최대한 유지한다.

## 현재 구조

- `Main.ahk`: 단일 진입점. 설정 로드, 트레이 구성, 앱 호스트 시작, 종료 처리를 담당한다.
- `lib/ShowDesktopOverride.ahk`: Win+D와 작업표시줄 우측 바탕화면 보기 버튼을 가로채고, 메모창을 보호한 상태로 일반 창만 최소화/복원한다.
- `lib/MemoWindow.ahk`: 제목표시줄 없는 리사이즈 가능 WebView2 메모카드 창을 호스팅한다.
- `lib/MemoWindowManager.ahk`: 메모 id 기준으로 여러 `MemoWindow` 인스턴스를 관리한다.
- `lib/ManagerWindow.ahk`: 일반 Windows GUI 형태의 메모 관리창을 호스팅한다.
- `lib/AppHost.ahk`: 숨겨진 WebView2 호스트다. Firestore를 구독하고 `desktopVisible == true` 메모만 카드 창으로 연다.
- `ui/index.html`: WebView2 공통 HTML 진입점이다.
- `ui/app.js`: `#host`, `#manager`, `#<memoId>`, `#new:<memoId>` 네 가지 라우트를 렌더링한다.
- `ui/style.css`: 스티커 메모카드와 메모 관리창의 CSS UI를 담당한다.

## 라우트 규칙

- `#host`: 숨겨진 Firestore 감시자. 화면 UI를 표시하지 않는다.
- `#manager`: 메모 관리창 UI.
- `#<memoId>`: 기존 Firestore 문서 하나를 메모카드로 연다. 문서가 없으면 자동 생성하지 않는다.
- `#new:<memoId>`: 사용자가 명시적으로 새 메모를 만들 때만 Firestore 문서를 생성한다.

이 규칙은 앱 시작 시 빈 메모가 임의로 생성되는 문제를 막기 위한 안전장치다.

## 트레이 동작

트레이 메뉴는 정식 계획과 동일하게 다음 항목만 제공한다.

- `메모 관리`: 메모 관리창을 표시하고 활성화한다.
- `새 메모`: 새 메모카드를 만든다.
- `모든 메모 숨김`: `desktopVisible=true`인 메모를 모두 숨김 처리하고 열린 카드 창을 닫는다.
- `종료`: 앱을 종료한다.

트레이 아이콘을 더블클릭하면 항상 메모 관리창을 표시한다.

## 메모카드 동작

- 제목표시줄은 없고, 상단 영역을 드래그하면 창이 이동한다.
- AHK `+Resize` 창 스타일로 테두리와 모서리 크기 조절을 지원한다.
- 우측 상단 `×`는 메모를 삭제하지 않고 `desktopVisible=false`로 저장한 뒤 창만 닫는다.
- 우측 하단 `삭제` 버튼은 확인 후 Firestore 문서 자체를 삭제한다.
- 텍스트 입력은 약 1초 debounce 후 Firestore에 저장한다.
- 위치와 크기는 `desktopBounds`와 로컬 `WindowStateStore`에 저장한다.

## 바탕화면 보기 동작

- Win+D와 작업표시줄 우측 바탕화면 보기 클릭은 네이티브 Show Desktop으로 넘기지 않는다.
- AHK가 직접 현재 일반 창의 Z-order를 기록하고 최소화한다.
- 메모카드 창은 보호 대상이므로 최소화하지 않는다.
- 복귀 시 기록된 창을 `SW_SHOWNOACTIVATE`로 복원하고 `BeginDeferWindowPos`/`DeferWindowPos`로 기존 Z-order를 최대한 재구성한다.
- 이전 포그라운드 창이 유효하면 마지막에 포커스를 되돌린다.

## 데이터 모델

공통 Firestore 컬렉션은 기존과 동일하게 `memos/{id}`를 사용한다.

기존 공통 필드:

- `id`
- `text`
- `images`
- `files`
- `pinned`
- `created`
- `updated`

데스크톱 전용 선택 필드:

- `desktopVisible`: 데스크톱 메모카드를 표시할지 여부
- `desktopBounds`: `{ x, y, w, h }` 창 위치와 크기
- `desktopUpdated`: 데스크톱 표시 상태 또는 bounds 변경 시각

## 현재 완료된 항목

- AHK 단일 진입점 기반으로 트레이, 메모카드, 관리창, 숨김 호스트를 통합했다.
- Win+D와 작업표시줄 우측 바탕화면 보기 오버라이드를 AHK 라이브러리로 정리했다.
- 메모카드는 WebView2/CSS 기반 스티커 UI로 렌더링한다.
- 메모카드는 WebView `ready` 이벤트가 도착하기 전까지 창을 숨긴 상태로 유지한다. WebView 초기화 실패 시 노란 AHK 배경 껍데기만 남지 않도록 한다.
- 메모 관리창은 전체 메모 목록, 검색, 표시, 숨김, 삭제, 새 메모 생성을 제공한다.
- 시작 시 관리창은 표시하지 않고, `desktopVisible == true`인 메모만 자동으로 연다.
- Firebase SDK는 WebView2 안정성을 위해 `ui/lib` 로컬 파일로 고정했다.
- `#new:<memoId>` 라우트를 추가하여 앱 시작 중 임의의 빈 메모가 생성되지 않도록 했다.
- 관리창에서 `표시`를 누른 직후 Firestore host의 이전 스냅샷이 도착해 방금 연 창을 다시 닫는 레이스를 막기 위해 짧은 grace window를 둔다.

## 확인된 주의사항

- Firestore 네트워크 또는 권한 오류가 있으면 관리창이 빈 화면이 아니라 오류 메시지를 표시해야 한다.
- 기존 테스트 중 만들어진 빈 Firestore 메모에 `desktopVisible=true`가 남아 있으면 앱 시작 시 그 메모가 다시 열릴 수 있다. 이 경우 메모카드의 `삭제` 또는 관리창의 `삭제`로 제거한다.
- Android 앱의 현재 `Memo.toMap()` 구현은 데스크톱 전용 필드를 보존하지 않는다. 데스크톱 필드 완전 보존을 위해 Android 모델/저장 로직에 후속 패치가 필요하다.
- 이미지/파일 첨부는 이번 AHK 1차 리팩토링에서 카드 UI에 직접 표시하지 않고, 기존 웹/안드 데이터 구조를 깨지 않는 수준으로 유지한다.

## 검증 체크리스트

- `AutoHotkey64.exe /Validate memo-desktop\Main.ahk`가 성공해야 한다.
- `node --check memo-desktop\ui\app.js`가 성공해야 한다.
- `Main.ahk` 실행 직후 관리창이 자동 표시되지 않아야 한다.
- Firestore에서 `desktopVisible == true`인 메모만 자동으로 카드 창으로 열려야 한다.
- 문서가 없는 기존 메모 라우트는 새 빈 메모를 자동 생성하지 않아야 한다.
- 트레이 더블클릭으로 관리창이 표시되어야 한다.
- 트레이 메뉴에는 `메모 관리`, `새 메모`, `모든 메모 숨김`, `종료`만 있어야 한다.
- 메모카드 우측 상단 `×`와 우측 하단 `삭제`가 명확하게 보여야 한다.
- Win+D와 작업표시줄 우측 바탕화면 보기 클릭이 같은 방식으로 동작해야 한다.
- Win+D 복귀 후 시작 메뉴가 열리거나 Windows 키가 눌린 상태처럼 남지 않아야 한다.
