# 안드로이드 메모 앱 구현 계획

> **프로젝트 요약**
> - Android: Kotlin + Jetpack Compose
> - Web: 기존 `memo-web/index.html`
> - Backend: Firebase Firestore 실시간 동기화
> - Attachments: GitHub uploads + jsDelivr CDN
> - 주요 기능: 메모 CRUD, 공유 연동, 검색, 고정, 정렬, 홈 화면 위젯, FCM 기반 위젯 실시간 갱신

---

## 현재 상태 요약

핵심 앱 기능과 위젯 실시간 동기화는 완료되었습니다. 남은 작업은 사용성 개선과 이미지 조작 편의 기능입니다.

- **Phase 0: 환경 구축 (완료)**  
  Android/Firebase 개발 환경 및 프로젝트 연결 완료.

- **Phase 1: Firebase 마이그레이션 (완료)**  
  기존 데이터 Firestore 이전 및 웹 실시간 동기화 적용 완료.

- **Phase 2: 안드로이드 핵심 기능 (완료)**  
  Compose 앱, Firestore Repository/ViewModel, 메모 목록/편집, GitHub 첨부 업로드 구현 완료.

- **Phase 3: 부가 기능 (완료)**  
  공유 연동, 홈 화면 위젯, 다크 모드, 검색, 고정/정렬, 편집 중 자동 스크롤 및 뷰포트 안정화 완료.

- **Phase 4: 위젯 실시간 갱신 (완료)**  
  XML RemoteViews 위젯, FCM data 메시지, Cloud Functions 배포를 통한 앱 종료 상태 위젯 즉시 갱신 완료.

---

## 완료된 작업

### Phase 0: 환경 구축 (완료)
- Android Studio/SDK/JDK 개발 환경 구성 완료.
- Firebase 프로젝트 및 Android/Web 앱 등록 완료.

### Phase 1: Firebase 마이그레이션 (완료)
- JSONBin.io 기존 데이터를 Firestore `memos/{id}` 구조로 이전 완료.
- 웹 앱에 Firestore SDK 및 실시간 `onSnapshot` 동기화 적용 완료.

### Phase 2: 안드로이드 핵심 기능 (완료)
- Android Compose 프로젝트 구성 및 Firebase/Coil/OkHttp 의존성 적용 완료.
- `Memo`, `FileAttachment`, `MemoRepository`, `MemoViewModel` 구현 완료.
- 메모 목록, 편집, 생성, 삭제, 첨부 파일/이미지 관리 구현 완료.
- GitHub 업로드/삭제 모듈 구현 완료.

### Phase 3: 부가 기능 (완료)
- **Task 3-1: 공유 연동 (완료)**  
  `ShareReceiverActivity` 기반 외부 텍스트/파일 공유 저장 완료.

- **Task 3-2: 홈 화면 위젯 (완료)**  
  Glance 구현 제거 후 XML layout + `AppWidgetProvider` + `RemoteViews` 기반 위젯 구현 완료.

- **Task 3-3: 다크 모드 (완료)**  
  Material3 테마 및 시스템 다크 모드 대응 완료.

- **Task 3-4: 검색 기능 (완료)**  
  메모 본문 및 첨부 파일명 기반 검색 필터링 구현 완료.

- **Task 3-5: 메모 고정 및 정렬 (완료)**  
  pinned 우선 정렬 및 생성일/수정일 정렬 구현 완료.

- **Task 3-6: 메모 편집 중 자동 스크롤 및 뷰포트 개선 (완료)**  
  편집 중 리스트 위치 안정화, `TextFieldValue` 기반 커서 유지, 커서 주변 자동 스크롤 구현 완료.

### Phase 4: 위젯 실시간 갱신 (완료)
- **Task 4-1: FCM 설정 (완료)**  
  `MemoFirebaseMessagingService`에서 FCM data 메시지 수신 시 위젯 즉시 갱신 구현 완료.

- **Task 4-2: Cloud Function 작성 및 배포 (완료)**  
  Firestore `memos/{memoId}` 변경 시 메모 payload를 포함한 Silent FCM 전송 구현 및 배포 완료.

---

## 완료된 추가 작업

### Task 5-1: 자동저장 시 수정일 정렬 반영 (완료)
- 수정일 순 정렬 상태에서 자동저장이 완료되는 순간 실제 정렬 순서를 재평가하도록 수정 완료.

### Task 5-2: 위젯 클릭 시 해당 메모 즉시 편집 (완료)
- 위젯 클릭 Intent에 memoId를 전달하고 앱 진입 시 해당 메모로 스크롤 및 포커스 처리 완료.

### Task 5-3: 첨부 이미지 전체보기 팝업 (완료)
- 메모 첨부 이미지를 터치하면 전체 이미지 팝업을 표시하도록 구현 완료.

### Task 5-4: 이미지 저장 버튼 및 터치 영역 개선 (완료)
- 첨부 이미지 우측 상단 액션에 저장 버튼 추가 완료.
- 삭제/저장 버튼 크기를 키워 터치 편의성 개선 완료.

### Task 5-5: 뷰포트 상하 여백 확보 (완료)
- 편집 중 자동 스크롤 시 커서 상하 여유 라인을 약 2줄로 늘려 시인성 개선 완료.
