# AGENTS.md

## Project

Voice Doc Flutter frontend.

목표:
- 회의 음성 파일을 선택하거나 녹음한다.
- FastAPI 백엔드에서 회의 레코드와 S3 presigned upload URL을 발급받는다.
- Flutter 앱이 presigned URL로 S3에 음성 파일을 직접 업로드한다.
- 업로드 성공 후 백엔드에 회의록 생성 작업 시작을 요청한다.
- 회의/job 상태를 polling하여 Transcribe 및 LLM 처리 진행 상황을 보여준다.
- 완료된 회의록 Markdown/JSON 결과를 앱에서 조회한다.

---

## Tech Stack

- Flutter
- Dart
- Material Design
- HTTP client package
- File picker or recorder package
- Optional: state management package after screen flow grows

---

## Backend Contract

Backend repository:
`../KB-AI-Hackerton-Backend`

Backend principle:
- API = thin routes
- Worker = long-running STT/LLM processing
- LLM and Transcribe must not be called directly from Flutter
- Flutter uploads audio to S3 only through backend-generated presigned URLs
- `POST /meetings/{meeting_id}/start` creates an internal worker job and returns `job_id`
- Local backend development requires two processes: FastAPI server and `worker.py`

Base URL must be environment-specific and must not be hardcoded across widgets.

Recommended local examples:
- Android emulator: `http://10.0.2.2:8000`
- iOS simulator: `http://localhost:8000`
- physical device: use the host machine LAN IP, for example `http://192.168.x.x:8000`

Backend local run:

```bash
# Terminal 1: API server
cd ../KB-AI-Hackerton-Backend/server
uv run uvicorn app.main:app --reload

# Terminal 2: Worker
cd ../KB-AI-Hackerton-Backend/server
uv run python worker.py
```

Docker Compose can run both processes together:

```bash
cd ../KB-AI-Hackerton-Backend/server
docker compose up --build
```

---

## API Flow

Flutter production flow:

1. `POST /meetings`
2. `POST /meetings/{meeting_id}/upload-url`
3. `PUT {upload_url}` directly to S3 with the selected audio bytes
4. `POST /meetings/{meeting_id}/start`
5. Poll `GET /meetings/{meeting_id}` or `GET /jobs/{job_id}`
6. When completed, call `GET /meetings/{meeting_id}/result`

Do not call Transcribe, Bedrock, or S3 SDK APIs directly from the app.

---

## API List

### Health Check

`GET /health`

Purpose:
- Check whether the API server is reachable.

Expected response:

```json
{
  "status": "ok"
}
```

### Create Meeting

`POST /meetings`

Purpose:
- Create a meeting row before audio upload.

Request:

```json
{
  "title": "주간 회의",
  "meeting_type": "unknown"
}
```

`meeting_type` values:
- `one_on_one`: 1:1 meeting, max 2 speakers
- `small`: small meeting, max 5 speakers
- `medium`: medium meeting, max 10 speakers
- `unknown`: default, max 8 speakers

Expected response:

```json
{
  "id": "meeting-uuid",
  "title": "주간 회의",
  "meeting_type": "unknown",
  "status": "created",
  "audio_s3_key": null,
  "transcript_s3_key": null,
  "minutes_json_s3_key": null,
  "minutes_markdown_s3_key": null,
  "summary": null,
  "error_message": null,
  "created_at": "2026-05-11T00:00:00Z",
  "updated_at": "2026-05-11T00:00:00Z"
}
```

### Create Upload URL

`POST /meetings/{meeting_id}/upload-url`

Purpose:
- Reserve an S3 object key and receive a presigned PUT URL.

Request:

```json
{
  "file_extension": "m4a",
  "content_type": "audio/mp4"
}
```

Expected response:

```json
{
  "upload_url": "https://...",
  "s3_key": "kb-ai-voicedoc/audio/{meeting_id}/original.m4a",
  "expires_in": 900
}
```

Flutter upload rule:
- Send the audio bytes with HTTP `PUT` to `upload_url`.
- Use the same `Content-Type` value requested from the backend.
- Treat non-2xx upload responses as failed uploads.

### Start Meeting Job

`POST /meetings/{meeting_id}/start`

Purpose:
- Tell the backend that S3 upload succeeded and enqueue the worker job.

Expected response:

```json
{
  "meeting_id": "meeting-uuid",
  "job_id": "job-uuid",
  "status": "queued"
}
```

### Get Meeting

`GET /meetings/{meeting_id}`

Purpose:
- Poll meeting status and basic metadata.

Expected response:

```json
{
  "id": "meeting-uuid",
  "title": "주간 회의",
  "meeting_type": "small",
  "status": "transcribing",
  "audio_s3_key": "kb-ai-voicedoc/audio/...",
  "transcript_s3_key": null,
  "minutes_json_s3_key": null,
  "minutes_markdown_s3_key": null,
  "summary": null,
  "error_message": null,
  "created_at": "2026-05-11T00:00:00Z",
  "updated_at": "2026-05-11T00:00:00Z"
}
```

Meeting status values:
- `created`
- `uploaded`
- `queued`
- `transcribing`
- `summarizing`
- `completed`
- `failed`

### Get Meeting Result

`GET /meetings/{meeting_id}/result`

Purpose:
- Fetch result metadata after completion.

Expected response:

```json
{
  "meeting_id": "meeting-uuid",
  "status": "completed",
  "title": "회의록 제목",
  "summary": "회의 요약 내용",
  "decisions": ["결정 사항"],
  "action_items": [
    {
      "owner": "담당자",
      "task": "할 일",
      "due_date": "미정"
    }
  ],
  "minutes_json_s3_key": "kb-ai-voicedoc/minutes/{meeting_id}/minutes.json",
  "minutes_markdown_s3_key": "kb-ai-voicedoc/minutes/{meeting_id}/minutes.md"
}
```

If status is not completed, keep showing the processing state instead of assuming the result is ready.

The backend currently returns result metadata at all statuses. `decisions` and `action_items` are available after the worker stores structured LLM output.

### Get Job

`GET /jobs/{job_id}`

Purpose:
- Poll worker job status when `job_id` is available from `/start`.

Expected response:

```json
{
  "id": "job-uuid",
  "meeting_id": "meeting-uuid",
  "job_type": "meeting_pipeline",
  "status": "running",
  "aws_job_name": "kb-ai-voicedoc-meeting-uuid",
  "attempt_count": 1,
  "error_message": null,
  "locked_at": "2026-05-14T00:00:00Z",
  "started_at": "2026-05-14T00:00:00Z",
  "completed_at": null,
  "created_at": "2026-05-11T00:00:00Z",
  "updated_at": "2026-05-11T00:00:00Z"
}
```

Job status values:
- `queued`
- `running`
- `completed`
- `failed`

### Dev Only Upload

`POST /meetings/{meeting_id}/upload`

Purpose:
- Development-only direct multipart upload for Swagger/local testing.

Flutter production builds must not depend on this endpoint.

---

## App Screens

Minimum MVP screens:
- Meeting list
- Create meeting / audio selection
- Upload progress
- Processing status
- Meeting result detail
- Error state with retry or return action

Avoid building a marketing landing page as the first screen. The app should open into the actual meeting workflow.

---

## Client Architecture

Recommended structure:

```text
lib/
 ├─ main.dart
 ├─ app/
 │   ├─ app.dart
 │   └─ router.dart
 ├─ core/
 │   ├─ config/
 │   ├─ network/
 │   └─ errors/
 ├─ features/
 │   └─ meetings/
 │       ├─ data/
 │       ├─ domain/
 │       └─ presentation/
 └─ shared/
     ├─ widgets/
     └─ theme/
```

Rules:
- Keep widgets focused on rendering and user interaction.
- Put HTTP calls in data/API classes, not directly in widgets.
- Put API DTO parsing in model classes with explicit types.
- Keep backend status strings mapped to a typed Dart enum.
- Keep upload/start/polling orchestration in a controller, notifier, bloc, or use case layer.

---

## Networking Rules

- Use one centralized API client for FastAPI calls.
- Use a separate upload method for S3 presigned URL `PUT` requests.
- Do not attach backend auth headers to the S3 presigned upload unless the backend explicitly requires it.
- Preserve `Content-Type` when uploading to S3.
- Add request timeout and clear error mapping.
- Poll with a controlled interval, for example 2-5 seconds.
- Stop polling when status is `completed` or `failed`.
- Do not start duplicate polling timers for the same meeting.
- Prefer polling `GET /jobs/{job_id}` after `/start`; use `GET /meetings/{meeting_id}` when restoring state after app restart.
- Treat HTTP `409` from `/start` as "job already in progress" and resume polling instead of creating a new meeting.

---

## Error Handling

Flutter must handle:
- API server unavailable
- S3 upload failure
- expired presigned URL
- meeting not found
- job already in progress
- worker not running locally, where status stays `queued`
- worker failure with `error_message`
- timeout while polling

Display user-facing Korean messages, but keep internal exception names and logs developer-readable.

---

## Secrets Rules

- Do not commit API secrets, AWS keys, Firebase service account JSON, APNs keys, or local `.env` files.
- Do not put AWS Access Key, Secret Access Key, or session token in Dart code.
- Flutter must not use AWS SDK credentials for S3 upload.
- Use backend-provided presigned URLs for upload.
- Environment-specific API base URLs should be configured through build flavors, `--dart-define`, or a local ignored config file.

---

## UI Rules

- Build the usable workflow first.
- Use Material components consistently.
- Keep status and upload progress visible.
- Use clear empty/loading/error states.
- Make buttons disabled while an upload or start request is in progress.
- Do not show implementation details such as S3 keys to end users unless in a debug screen.
- Korean UI text should be concise and action-oriented.

---

## Local Run

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

Backend local run is managed in `../KB-AI-Hackerton-Backend/server`.
For an end-to-end local backend flow, run both `uvicorn` and `worker.py`.

---

## Final Principle

Flutter = user workflow
FastAPI = request/status API
S3 = direct audio upload through presigned URL
Worker = Transcribe and Bedrock processing
