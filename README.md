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
