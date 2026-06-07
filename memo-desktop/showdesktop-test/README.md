# ShowDesktopTest

Windows `Show Desktop`(`Win+D` 또는 작업표시줄 우측 바탕화면 보기) 동작 중에도 앱을 바탕화면/아이콘 위에 유지하고, 복귀 시 기존 z-order를 되살릴 수 있는지 검증하기 위한 WinForms 테스트 앱입니다.

## 목표

- 실행 시 일반적인 Windows GUI 창으로 동작합니다.
- 평상시에는 일반 앱들과 같은 z-order 규칙을 따릅니다.
- Show Desktop 진입 시 다른 일반 앱은 사라지더라도 이 앱은 바탕화면과 바탕화면 아이콘 위에 남습니다.
- Show Desktop 복귀 시 기존 z-order에 가깝게 복원합니다.
- Show Desktop 중 표시되는 대리 창과 메인 창의 텍스트, 위치, 크기를 동기화합니다.

## 최종 전략

초기에는 메인 WinForms 창 자체를 `ShowWindowAsync`, `SetWindowPos`, `WorkerW`/`Progman` reparent 방식으로 되살리려 했습니다. 하지만 일부 Windows Shell 환경에서는 Win32/DWM 상태값이 `Visible=true`, `CloakFlags=0`이어도 실제 화면 픽셀에는 창이 보이지 않았습니다.

그래서 상태값이 아니라 실제 화면 픽셀을 검사하는 `PixelVisibilityProbe`를 추가했고, 최종적으로 아래 방식이 성공했습니다.

1. 평상시에는 메인 창이 일반 top-level window로 동작합니다.
2. Show Desktop 진입을 WinEvent와 상태 변화로 감지합니다.
3. 메인 창의 실제 픽셀이 보이지 않으면 `top-level-surrogate`를 띄웁니다.
4. surrogate는 `HWND_TOPMOST` top-level WinForms 창이며, 텍스트 편집이 가능한 `TextBox`를 포함합니다.
5. surrogate와 메인 창은 텍스트, 위치, 크기를 양방향 동기화합니다.
6. Show Desktop 복귀 시 surrogate를 숨기고 메인 창을 복원합니다.
7. 저장된 z-order snapshot에 따라 원래 위치로 되돌리고, Shell 복구 타이밍을 고려해 짧은 settle retry를 한 번 더 수행합니다.

## 주요 개념

- **surrogate**: Show Desktop 중 메인 창 대신 화면에 보이는 대리 창입니다.
- **top-level-surrogate**: `WorkerW`나 `Progman`의 자식 창이 아니라 독립 top-level window로 띄운 surrogate입니다. 이 방식이 실제 픽셀 가시성 검증을 통과했습니다.
- **foreground**: Windows가 현재 사용자 조작 대상으로 보는 창입니다. surrogate가 foreground가 되어도 외부 앱으로 오판하지 않도록, surrogate hwnd를 이 앱의 일부로 취급합니다.
- **desktop-fallback-attach**: 메인 창 픽셀이 보이지 않을 때 surrogate 표시 전략을 붙였다는 로그 이벤트입니다.
- **PixelVisible**: 화면에서 실제로 fuchsia beacon 픽셀이 샘플링되는지 확인한 결과입니다. Win32의 visible/cloak 상태보다 더 신뢰할 수 있는 최종 판정값입니다.

## 구현 파일

- `MainForm.cs`: 메인 WinForms UI, hotkey, 텍스트/Bounds 동기화 콜백.
- `ShowDesktopController.cs`: Show Desktop 감지, 생존 처리, z-order snapshot/restore, 이벤트 로그.
- `DesktopLayerFallback.cs`: surrogate attach/detach 및 fallback 전략.
- `EditableSurrogateWindow.cs`: Show Desktop 중 표시되는 편집 가능한 surrogate 창.
- `WindowProbe.cs`: top-level window enumeration, z-order, Win32/DWM 상태 수집.
- `PixelVisibilityProbe.cs`: 실제 화면 픽셀 샘플링.
- `EventLogger.cs`: `%LocalAppData%\ShowDesktopTest\events.jsonl` JSONL 로그 기록.

## 빌드

```powershell
dotnet build -c Release
```

빌드 결과:

```text
bin\Release\net8.0-windows\ShowDesktopTest.exe
```

## 수동 검증 절차

1. 계산기를 실행합니다.
2. `ShowDesktopTest.exe`를 실행합니다.
3. 그림판을 실행합니다.
4. 원하는 z-order를 만든 뒤 1초 정도 기다립니다.
5. 필요 시 `Ctrl+Alt+S`로 snapshot을 저장합니다.
6. `Win+D` 또는 작업표시줄 우측 바탕화면 보기 버튼을 누릅니다.
7. Show Desktop 상태에서 surrogate가 보이는지 확인합니다.
8. surrogate의 텍스트를 편집하거나 창을 이동/크기 변경합니다.
9. 다시 `Win+D` 또는 바탕화면 보기 버튼으로 복귀합니다.
10. 메인 창의 텍스트, 위치, 크기, z-order가 복원되는지 확인합니다.

## 로그

이벤트 로그는 다음 위치에 저장됩니다.

```text
%LocalAppData%\ShowDesktopTest\events.jsonl
```

중요 이벤트:

- `show-desktop-enter`: Show Desktop 진입 감지와 사용된 z-order snapshot.
- `desktop-fallback-attach`: surrogate 표시 시도와 픽셀 가시성 결과.
- `desktop-fallback-detach`: Show Desktop 복귀 시 surrogate 제거.
- `restore-zorder`: snapshot 기반 z-order 복원 결과.
- `restore-zorder` with `:settle-retry`: Shell 복구 이후 한 번 더 수행한 안정화 복원.
- `pixel-visibility`: 실제 화면 픽셀 샘플링 결과.

## 확인된 실패 경로와 결론

- `WorkerW`/`Progman` 자식 창 surrogate는 아이콘을 가리는 듯한 흔적은 있었지만 실제 픽셀 검증에 실패했습니다.
- 메인 창이 `Visible=true`, `CloakFlags=0`이어도 실제 화면에서는 보이지 않을 수 있었습니다.
- surrogate가 foreground가 되는 순간을 Show Desktop 복귀로 오판하면 surrogate가 즉시 사라지는 문제가 있었습니다.
- 앱 자신이 foreground일 때 z-order snapshot을 갱신하지 않으면, 원래 최상위였던 상태가 저장되지 않아 복귀 시 하위로 밀릴 수 있었습니다.

최종적으로는 `top-level editable surrogate + 실제 픽셀 검증 + 메인 창/대리 창 동기화 + z-order settle retry` 조합이 가장 안정적이었습니다.
