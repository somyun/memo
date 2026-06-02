# 📱 안드로이드 메모 앱 — 전체 구현 계획서 (수정본)

> **프로젝트 요약**
> - 플랫폼: Android (Kotlin + Jetpack Compose) + 기존 웹 (index.html)
> - 백엔드: Firebase Firestore 실시간 연동
> - 파일/이미지 저장: GitHub (기존 유지, jsDelivr CDN 연동)
> - 핵심 기능: 실시간 동기화, 홈 화면 위젯, 공유 연동, 다크 모드, 검색, 고정, 정렬

---

## 📊 현재까지의 구현 및 완료 상황 요약

현재 프로젝트는 핵심 아키텍처와 중요 기능이 대부분 완성된 상태이며, 일부 미진한 홈 위젯 연동 부분을 안정적인 설계로 리팩토링하는 단계에 있습니다.

* **Phase 0: 환경 구축 (100% 완료)**
  - Android Studio 개발 환경 셋업 완료.
  - Firebase 콘솔에 웹 및 안드로이드 앱 등록 완료.
* **Phase 1: Firebase 마이그레이션 - 웹 (100% 완료)**
  - JSONBin.io 기존 데이터를 Firestore로 이관 완료.
  - `memo-web/index.html`에 Firebase SDK를 탑재하여 실시간 동기화(`onSnapshot`), 자동저장, 로컬 캔버스 압축 기능 완료.
* **Phase 2: 안드로이드 앱 핵심 기능 (100% 완료)**
  - Compose Empty Activity 프로젝트 뼈대 및 google-services.json 연동 완료.
  - `MemoRepository`(Firestore CRUD) 및 `MemoViewModel` 상태 관리 구현 완료.
  - `MemoListScreen.kt` 메인 목록 렌더링, Pull-to-refresh 및 편집 로직 완료.
  - `GitHubUploader.kt` + OkHttp 연동을 이용한 모노레포 `uploads/` 저장소 이미지/파일 업로드 연동 완료.
* **Phase 3: 부가 기능 (80% 완료)**
  - **Task 3-1: 공유 연동 (완료)**: `ShareReceiverActivity`를 통해 외부 공유 인텐트(텍스트, 파일)를 수신해 즉시 Firestore/GitHub에 저장 완료.
  - **Task 3-2: 홈 화면 위젯 (진행 중 - 방향 수정)**:
    - ⚠️ **이슈 사항**: 최신의 선언형 Glance API(`androidx.glance`) 기반으로 구현을 시도하였으나, Glance의 라이브러리 성숙도 부족, 런타임 RemoteViews 변환 오류, 레퍼런스 부족 등으로 인해 실제 런처 위젯 배포 시 갱신이 누락되거나 에러가 발생하는 오작동 현상 식별.
    - 💡 **수정 방향**: Glance API를 완전 걷어내고, Android OS에서 오랜 기간 안정성이 입증된 **전통적인 XML 레이아웃 + AppWidgetProvider + RemoteViews** 방식으로 전면 리팩토링하여 안정적인 위젯 갱신을 보장하기로 결정.
  - **Task 3-3 ~ 3-5: 다크 모드, 검색, 고정 및 정렬 (완료)**: 테마 대응 및 `MemoListScreen` 내부 필터링/정렬 비즈니스 로직 적용 완료.
* **Phase 4: 위젯 실시간 갱신 (보류 / 진행 예정)**
  - Cloud Functions 및 FCM을 통한 위젯 무중단 실시간 갱신 구조 구축 예정.

---

## Phase 0: 환경 구축

### Task 0-1: Android Studio 설치 (완료)
* SDK 버전 35( compileSdk 35, targetSdk 35) 및 JDK 11 개발 환경 설치 완료.

### Task 0-2: Firebase 프로젝트 설정 (완료)
* Firestore Database 활성화 (서울 리전 - `asia-northeast3`).
* `memo-web` 및 `memo-android` 앱 각각 연동용 설정 구성 및 key 배포 완료.

---

## Phase 1: Firebase 마이그레이션 (웹) (완료)

### Task 1-1: 기존 데이터 마이그레이션 스크립트 (완료)
* JSONBin.io 데이터의 개별 Firestore Document 구조(`memos/{id}`) 이관 완료.

### Task 1-2: index.html Firebase SDK 적용 (완료)
* 웹에서의 Firestore 실시간 리스너(`onSnapshot`) 탑재 및 파일 업로드 시 base64 프리뷰를 통한 CDN 캐시 딜레이 대응 설계 완료.

---

## Phase 2: 안드로이드 앱 핵심 (완료)

### Task 2-1: 프로젝트 생성 및 기본 구성 (완료)
* Empty Activity template 및 `build.gradle.kts` 내 SDK 35 타겟 의존성(Firestore, Messaging, Coil, OkHttp) 구성 완료.
* 불필요해진 `androidTest` 및 `test` 테스트 디렉토리는 정리 완료.

### Task 2-2: 데이터 모델 및 Repository (완료)
* `Memo` 및 `FileAttachment` 데이터 클래스 매핑 완료.
* `MemoRepository`를 통한 Coroutine/Flow 기반 CRUD 구축 완료.

### Task 2-3: 메모 목록 화면 (완료)
* 메인 `MemoListScreen` 내에 LazyColumn 기반 메모 카드 리스팅 및 Pull-to-refresh 구현 완료.

### Task 2-4: 메모 편집 화면 (완료)
* TextField 텍스트 편집, 이미지/파일 첨부, 갤러리 픽커 연동 및 Firestore 연계 완료.

### Task 2-5: GitHub 업로드 모듈 (완료)
* OkHttp를 이용한 REST API 호출 모듈 개발 완료.

---

## Phase 3: 부가 기능

### Task 3-1: 공유 연동 (Share Intent) (완료)
* `ShareReceiverActivity.kt` 작성을 통해 타 앱으로부터 전송된 공유 콘텐츠 데이터 저장 연동 완료.

### Task 3-2: 홈 화면 위젯 (재설계 및 전면 리팩토링 진행)

> [!WARNING]
> **Glance API 걷어내기**: Glance API는 Compose 코드 스타일로 위젯을 작성하도록 지원하나 런타임의 RemoteViews 변환 단계를 거치면서 예측 불가능한 UI 깨짐 및 갱신 거부 현상이 빈번합니다. 따라서 Native Android **XML RemoteViews + AppWidgetProvider** 기반의 견고한 위젯 아키텍처로 리팩토링합니다.

```
작업 내용:
1. Glance 라이브러리 및 관련 임포트 제거
2. 전통적인 XML 위젯 레이아웃 정의 (res/layout/widget_memo.xml)
   - 스티커 메모 질감의 노란 배경 (#FEF9C3) 및 둥근 모서리 적용
   - 텍스트 뷰 (메모 본문용 TextView)
   - 날짜 뷰 (수정시간용 TextView)
3. AppWidgetProvider 구현 (MemoWidgetProvider.kt)
4. 위젯 설정 화면 수정 (MemoWidgetConfigActivity.kt)
5. 터치 시 동작: 해당 메모 상세 편집(MainActivity)으로 딥링크 진입
```

### Task 3-3: 다크 모드 (완료)
* Compose Material3 Dynamic Color 및 시스템 설정 기준 다크테마 완벽 대응 완료.

### Task 3-4: 검색 기능 (완료)
* 메인 AppBar에서 검색어 변경 시 Firestore 스냅샷 리스트를 실시간으로 인메모리 필터링하여 반응형으로 목록 갱신 완료.

### Task 3-5: 메모 고정 및 정렬 (완료)
* Firestore `pinned` 속성을 이용해 최상단 고정 및 수정일/작성일 기준 내림차순/오름차순 정렬 비즈니스 로직 적용 완료.

### Task 3-6: 메모 편집 시 자동 스크롤 및 뷰포트 개선 (진행 예정)

> [!IMPORTANT]
> **실시간 정렬 시 요동 방지 및 커서 가시성 확보**: 
> 1글자 단위로 수정시간이 업데이트되어 목록 순서가 바뀔 때 화면이 튀는 현상을 막고, 키보드가 솟아올랐을 때 텍스트 필드의 커서가 뷰포트 밖으로 밀리지 않도록 자동 스크롤 제어를 설계합니다.

```
추천 작업 내용:
1. 편집 중 실시간 정렬 보류 및 지연 반영
   - 사용자가 메모를 편집하기 시작하여 포커스를 가진 동안(activeEditingMemoId != null)에는 실시간으로 수정시간이 변경되더라도, 목록의 물리적인 스택 순서 재정렬(Re-ordering)을 일시적으로 보류합니다.
   - 포커스를 잃는 시점(onFocusChanged = false) 또는 일정 시간 무입력 상태가 유지될 때 정렬 순서를 재평가 및 리스트 갱신 처리합니다.
2. 커서 위치 기반 뷰포트 자동 스크롤 연동
   - BringIntoViewRequester를 개별 BasicTextField에 부여하고, 입력(Selection/Cursor) 변화 감지 시 `bringIntoView()`를 트리거하여 커서가 속한 텍스트 줄을 강제로 유효 뷰포트 영역(화면 전체 - 키보드 - 툴바) 안으로 당깁니다.
   - Modifier.imePadding() 뿐 아니라 키보드가 활성화되었을 때 listState.animateScrollToItem()을 함께 제어하여 포커스 중인 텍스트 필드의 전체 높이가 키보드 위에 완벽하게 정렬되도록 조정합니다.
3. 상태 제어 최적화 (TextFieldValue 도입)
   - 단순 String 상태 제어를 TextFieldValue(text, selection) 모델로 전환하여 리스트 갱신 시 발생하는 커서 포지션 리셋 및 스크롤 튐 문제를 완전히 차단합니다.
```

---


## Phase 4: 위젯 실시간 갱신

### Task 4-1: FCM 설정 (진행 예정)
* 클라이언트 단에 FCM 백그라운드 리시버를 배치하여 데이터 메시지 감지 시 `MemoWidgetProvider`로 브로드캐스트 발송 유도.

### Task 4-2: Cloud Function 작성 (진행 예정)
* Firestore `memos/{memoId}`의 `onWrite` 트리거 발생 시, 해당 메모를 보여주고 있는 기기의 FCM 토큰 목록을 조회하여 Silent 푸시 전송.

---