# KB-AI-Hackerton-Frontend

Voice Doc Flutter frontend.

이 앱은 FastAPI 백엔드와 통신해 회의 음성 업로드, 회의록 생성 작업 시작, 처리 상태 polling, 결과 조회를 수행합니다.

## Backend Flow

```text
Flutter App
  -> POST /meetings
  -> POST /meetings/{id}/upload-url
  -> PUT presigned S3 upload_url
  -> POST /meetings/{id}/start
  -> GET /jobs/{job_id} 또는 GET /meetings/{id}
  -> GET /meetings/{id}/result
```

Flutter는 Transcribe, Bedrock, AWS SDK를 직접 호출하지 않습니다.

## Local Backend

백엔드는 API 서버와 worker가 분리되어 있습니다. 로컬 end-to-end 테스트에는 터미널 2개가 필요합니다.

```bash
# Terminal 1
cd ../KB-AI-Hackerton-Backend/server
uv run uvicorn app.main:app --reload
```

```bash
# Terminal 2
cd ../KB-AI-Hackerton-Backend/server
uv run python worker.py
```

Docker Compose를 쓰면 API와 worker를 함께 실행할 수 있습니다.

```bash
cd ../KB-AI-Hackerton-Backend/server
docker compose up --build
```

## Flutter Local Run

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

## API Base URL

- iOS simulator: `http://localhost:8000`
- Android emulator: `http://10.0.2.2:8000`
- physical device: use the host machine LAN IP, for example `http://192.168.x.x:8000`

API base URL은 widget 안에 직접 hardcode하지 말고 build config, `--dart-define`, 또는 local ignored config로 관리합니다.
