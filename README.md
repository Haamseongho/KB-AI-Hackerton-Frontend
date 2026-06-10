# KB-AI-Hackerton-Frontend

Voice Doc Flutter frontend.

Flutter 앱은 FastAPI backend를 통해 실시간 STT, 회의록 생성, S3 결과 저장 흐름을 실행합니다. Flutter는 Amazon Transcribe, Bedrock, S3 SDK를 직접 호출하지 않습니다.

## Current Backend

기본 backend endpoint는 EC2 dev 서버입니다.

```text
API_BASE_URL=http://13.124.81.217:8080
WS_BASE_URL=ws://13.124.81.217:8080
```

`lib/core/config/app_config.dart`에 기본값이 설정되어 있어 Xcode/VSCode에서 직접 실행해도 EC2 backend를 봅니다. 필요하면 `--dart-define`으로 override할 수 있습니다.

## Realtime Flow

```text
Flutter App
  -> POST /meetings
  -> WS /ws/meetings/{id}/transcribe
  -> send 16 kHz mono PCM chunks
  -> receive transcript.partial / transcript.final
  -> POST /meetings/{id}/minutes-from-realtime
  -> receive minutes_json_s3_key / minutes_markdown_s3_key / pdf_s3_key
```

실시간 녹음 세션은 녹음을 시작한 로컬 회의방에 고정됩니다. 녹음 중 목록으로
돌아가 다른 회의방을 열어도 WebSocket 전사 이벤트와 저장용 녹음 파일은 시작한
회의방에만 연결되며, 해당 녹음을 종료하기 전에는 다른 회의방에서 새 녹음을
시작할 수 없습니다.

## Batch Flow

백엔드는 배치 업로드 계약을 제공하지만 Flutter의 전체 UI 흐름은 단계적으로
연결 중입니다.

```text
Saved audio file
  -> POST /meetings/{id}/upload-url
  -> PUT audio bytes to the presigned URL
  -> POST /meetings/{id}/start
  -> poll GET /jobs/{job_id}
  -> GET /meetings/{id}/result
```

현재 백엔드 `/start`는 배치 전사 완료 후 회의록 생성까지 이어서 실행합니다.
배치 전사문 원문 조회처럼 아직 백엔드 API가 없는 기능은 앱에서 지원 예정 안내로
표시합니다.

## Android Team Run

Android 팀원 실행 가이드는 다음 문서를 참고합니다.

[docs/android_team_run_guide.md](docs/android_team_run_guide.md)

macOS:

```bash
./scripts/run_android_ec2.sh
```

Windows PowerShell:

```powershell
.\scripts\run_android_ec2.ps1
```

디버그 APK 빌드:

```bash
./scripts/build_android_debug_apk_ec2.sh
```

```powershell
.\scripts\build_android_debug_apk_ec2.ps1
```

## Flutter Checks

```bash
flutter pub get
flutter analyze
flutter test
```

## Local Persistence

회의방, backend meeting id, transcript segment, recording metadata는 SQLite(`voice_doc_flutter.db`)에 저장됩니다. 앱을 완전히 종료한 뒤 다시 실행해도 런타임에 생성한 room이 목록에 남아야 합니다.
