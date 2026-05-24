# AGENTS.md

## Project

Voice Doc Flutter frontend.

2026-05-20 회의 이후 앱 방향은 S3 업로드 후 일괄 Transcribe 처리에서 실시간 STT 중심으로 변경되었다.

목표:
- Flutter 앱에서 회의방을 생성하고 녹음을 시작한다.
- 녹음 중 오디오 chunk를 FastAPI WebSocket으로 전송한다.
- 백엔드는 Amazon Transcribe Streaming을 호출하고 partial/final transcript를 WebSocket으로 반환한다.
- Flutter 앱은 partial transcript를 실시간으로 표시하고 final transcript를 누적 저장한다.
- 녹음 종료 시 녹음 파일과 transcript를 로컬 DB/로컬 파일에 저장한다.
- 저장된 녹음 파일이 많아져도 meeting_id, 날짜, 제목으로 찾아 다시 열 수 있어야 한다.
- 선택한 녹음 파일과 transcript는 REST API로 presigned URL을 받아 S3에 업로드할 수 있어야 한다.
- 녹음 종료 후 또는 업로드 후 LangGraph / Bedrock 요약 작업을 요청하고 결과를 앱에서 조회한다.

Primary demo flow:

```text
Flutter App
  -> realtime audio chunk
  -> WebSocket API / FastAPI WebSocket
  -> Amazon Transcribe Streaming
  -> receive partial transcript
  -> render live transcript in app
  -> save final transcript locally
  -> after recording ends, request LangGraph / Bedrock summary
```

Secondary storage/upload flow:

```text
Saved local recording
  -> select by meeting_id/date/title
  -> request backend presigned upload URL
  -> upload recording/transcript to S3
  -> update meeting storage metadata
  -> uploaded assets remain accessible from the meeting room
```

Flutter must not call Amazon Transcribe, Bedrock, S3 SDK, or LangGraph directly.

---

## Tech Stack

- Flutter
- Dart
- Material Design
- HTTP client package for REST API calls
- WebSocket client package for realtime STT
- Recorder package for microphone capture and audio file creation
- Local DB package for meetings, jobs, recordings, and transcript metadata
- File picker/file opener package only where local file selection or preview is needed
- Optional state management package after screen flow grows

---

## Backend Contract

Backend repository:
`../KB-AI-Hackerton-Backend`

Backend principle:
- API = thin REST and WebSocket routes
- Backend owns Amazon Transcribe Streaming, LangGraph, Bedrock, and S3 integration
- Flutter sends microphone audio chunks only to backend WebSocket
- Flutter uploads saved recording files to S3 only through backend-generated presigned URLs
- Flutter requests summary/minutes generation through backend REST API
- Long-running summary/minutes jobs are backend/worker responsibilities
- Base URL and WebSocket URL must be environment-specific and must not be hardcoded across widgets

Recommended local examples:
- Android emulator REST: `http://10.0.2.2:8000`
- Android emulator WS: `ws://10.0.2.2:8000`
- iOS simulator REST: `http://localhost:8000`
- iOS simulator WS: `ws://localhost:8000`
- physical device: use the host machine LAN IP, for example `http://192.168.x.x:8000` and `ws://192.168.x.x:8000`

Environment config should use build flavors, `--dart-define`, or a local ignored config file:
- `API_BASE_URL`
- `WS_BASE_URL`

Backend local run is managed in `../KB-AI-Hackerton-Backend/server`.
Run the FastAPI server and any required worker process for end-to-end local testing.

---

## Core App Responsibilities

### Recording

- Request microphone permission before recording.
- Start, pause, resume, and stop recording from the meeting room detail screen.
- Persist the final recording file locally with stable metadata.
- Treat realtime STT audio and saved recording files as separate concerns:
  - realtime STT stream sends backend-compatible PCM chunks to FastAPI WebSocket.
  - saved recording file may be `m4a`, `wav`, or another locally supported format.
  - local metadata must record both the saved file content type and the realtime stream format used for transcription.
- Show clear recording, paused, completed, and failed states.
- Do not lose transcript text when recording is paused.
- Ask whether to save the recording file before leaving a paused/active room when needed.

### Realtime Transcription

- Open a WebSocket session when recording starts.
- Send PCM audio chunks in the backend-required format.
- The web frontend demo streams PCM audio to FastAPI and waits for AWS transcript events; Flutter should mirror that behavior.
- Render partial transcript immediately without committing it as final text.
- Replace partial transcript when a newer partial arrives.
- Append final transcript segments to the saved transcript stream.
- Auto-scroll live transcript by default, with a visible on/off state.
- Close the WebSocket cleanly when recording stops or the user leaves the room.
- Pause behavior must match backend capability:
  - if backend supports `pause` / `resume`, send those control events.
  - if backend does not support pausing a Transcribe stream, close the current stream on pause and open a new stream segment when recording resumes.
  - in either case, preserve accumulated transcript and local recording continuity in the meeting room UI.
- Keep stream/session metadata locally, for example `stream_session_id`, `segment_index`, `started_at`, `ended_at`, and `ended_reason`.

### Local DB and Files

Local persistence must support at least:
- meetings
- jobs
- recordings
- transcript segments
- storage/upload metadata

Meetings and jobs need fields that connect local recordings to backend IDs:
- `meeting_id`
- `room_title`
- `meeting_type`
- `status`
- `recording_file_path`
- `recording_content_type`
- `recording_duration_ms`
- `realtime_audio_encoding`
- `realtime_sample_rate`
- `realtime_channels`
- `transcript_file_path`
- `transcript_text`
- `stream_session_id`
- `stream_segment_count`
- `summary`
- `storage_type`
- `audio_s3_key`
- `transcript_s3_key`
- `minutes_s3_key`
- `created_at`
- `updated_at`

Recordings must be searchable by:
- title
- meeting_id
- date
- local status
- upload status

### REST API Calls

REST calls should be wired even if the initial UI is simple:
- create meeting room
- update meeting metadata
- request presigned URL for recording upload
- upload recording/transcript with the presigned URL
- mark upload complete
- request summary/minutes generation
- fetch summary/minutes result

Buttons can be simple during MVP, but calls must live in API/data classes rather than directly inside widgets.

---

## Provisional API Flow

The exact backend endpoint names may change. Keep Flutter code centralized so route changes are isolated.

### Create Meeting Room

`POST /meetings`

Purpose:
- Create a meeting room before recording.

Request:

```json
{
  "title": "AWS Architecture Review",
  "meeting_type": "unknown",
  "storage_metadata": {
    "type": "local_db"
  }
}
```

Expected response:

```json
{
  "id": "meeting-uuid",
  "meeting_id": "MTG-20260521-002",
  "title": "AWS Architecture Review",
  "meeting_type": "unknown",
  "status": "ready",
  "storage_metadata": {
    "type": "local_db"
  },
  "created_at": "2026-05-21T02:00:00Z",
  "updated_at": "2026-05-21T02:00:00Z"
}
```

### Live Transcription WebSocket

Provisional endpoint:

`WS /ws/meetings/{meeting_id}/transcribe`

Purpose:
- Stream microphone audio chunks to backend.
- Receive partial/final transcript events from Amazon Transcribe Streaming through backend.

Client events:

```json
{
  "type": "start",
  "meeting_id": "MTG-20260521-002",
  "sample_rate": 16000,
  "encoding": "pcm_s16le",
  "channels": 1,
  "chunk_duration_ms": 100,
  "language_code": "ko-KR"
}
```

Binary audio chunk:

```text
raw PCM bytes, 16-bit little-endian mono unless backend says otherwise
```

```json
{
  "type": "pause"
}
```

```json
{
  "type": "resume"
}
```

```json
{
  "type": "stop"
}
```

Server events:

```json
{
  "type": "transcription_status",
  "status": "transcribing",
  "message": "Backend status: transcribing"
}
```

```json
{
  "type": "partial_transcript",
  "text": "오늘 회의에서는",
  "speaker": null,
  "started_at_ms": 1240,
  "ended_at_ms": 2180
}
```

```json
{
  "type": "final_transcript",
  "text": "오늘 회의에서는 실시간 STT 구조를 확정합니다.",
  "speaker": "Speaker 1",
  "started_at_ms": 1240,
  "ended_at_ms": 4920
}
```

```json
{
  "type": "error",
  "message": "Transcribe stream failed"
}
```

Development-only event:

```json
{
  "type": "test_event",
  "text": "Realtime transcription test event."
}
```

Purpose:
- The web demo has a `Test Event` button for local UI testing.
- Flutter may include a debug-only test event button while WebSocket/Transcribe integration is incomplete.
- Production UI must not depend on test events for transcript creation.

### Create Upload URL

`POST /meetings/{meeting_id}/upload-url`

Purpose:
- Reserve S3 object keys and receive presigned PUT URLs for saved local assets.

Request:

```json
{
  "assets": [
    {
      "asset_type": "recording",
      "file_extension": "m4a",
      "content_type": "audio/mp4"
    },
    {
      "asset_type": "transcript",
      "file_extension": "txt",
      "content_type": "text/plain"
    }
  ]
}
```

Expected response:

```json
{
  "assets": [
    {
      "asset_type": "recording",
      "upload_url": "https://...",
      "s3_key": "kb-ai-voicedoc/audio/{meeting_id}/original.m4a",
      "expires_in": 900
    },
    {
      "asset_type": "transcript",
      "upload_url": "https://...",
      "s3_key": "kb-ai-voicedoc/transcripts/{meeting_id}/transcript.txt",
      "expires_in": 900
    }
  ]
}
```

Flutter upload rule:
- Send bytes with HTTP `PUT` to each `upload_url`.
- Use the same `Content-Type` requested from the backend.
- Do not attach backend auth headers to S3 presigned uploads unless the backend explicitly requires it.
- Treat non-2xx upload responses as failed uploads.

### Mark Upload Complete

`POST /meetings/{meeting_id}/upload-complete`

Purpose:
- Tell backend that local recording/transcript assets were uploaded successfully.

Request:

```json
{
  "audio_s3_key": "kb-ai-voicedoc/audio/{meeting_id}/original.m4a",
  "transcript_s3_key": "kb-ai-voicedoc/transcripts/{meeting_id}/transcript.txt"
}
```

### Start Summary Job

`POST /meetings/{meeting_id}/summarize`

Purpose:
- Request LangGraph / Bedrock summary after recording is finished and transcript is available.

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
- Fetch meeting metadata and restore state.

Meeting status values:
- `ready`
- `recording`
- `paused`
- `transcribing`
- `transcription_completed`
- `summary_queued`
- `summarizing`
- `completed`
- `failed`
- `uploaded`

### Get Meeting Result

`GET /meetings/{meeting_id}/result`

Purpose:
- Fetch summary/minutes metadata after LangGraph / Bedrock processing.

If the result is not completed, keep showing the current processing state instead of assuming the result is ready.

---

## App Screens

Minimum MVP screens:
- Meeting Rooms list
- Create Meeting Room bottom sheet/modal
- Meeting Room detail with live transcript
- Recording controls
- Save recording confirmation modal
- Upload to S3 confirmation modal
- Local recording file/resources section
- Meeting result detail
- Error state with retry or return action

Avoid building a marketing landing page as the first screen. The app should open into the actual meeting workflow.

---

## UI / UX Reference

The Flutter UI should follow the Vercel Next.js web frontend shown in the supplied screenshots.

Core visual direction:
- Clean mobile-first meeting workflow.
- White/off-white background.
- KB-like yellow primary action color.
- Dark navy/black text.
- Rounded cards with subtle borders and shadows.
- Status chips for `Ready`, `Recording`, `Paused`, `Completed`, `Uploaded`.
- Compact icon + label action buttons.
- Large, readable meeting title and meeting_id.

Meeting Rooms list:
- Header: `Meeting Rooms`
- Primary action: `New Room`
- Search by room title or meeting_id.
- Meeting cards show title, meeting_id, date/time, status chip, overflow menu, and actions.
- Card actions include `Recording`, `Transcript`, and `Upload to S3`.
- Do not show raw S3 keys in the main UI.

Create Meeting Room:
- Use a bottom sheet or modal.
- Fields: room title, meeting type, storage option, optional notes.
- Storage option starts with `Local DB`; AWS RDS can be shown only if backend supports it.
- Show a schema/metadata preview if it helps the demo.

Meeting Room detail:
- Header includes back button, room icon, title, meeting_id, date/time, and upload action.
- Live transcript panel shows transcript lines with timestamp and speaker label when available.
- Show backend/WebSocket status messages such as `Backend status: transcribing`, `Final transcript received`, and `Transcription is paused`.
- Partial transcript should visibly update in place.
- Final transcript should remain stable.
- Footer shows live/paused/completed transcription state and auto-scroll status.
- Bottom controls include record, pause/resume, and leave room.
- A `Test Event` control may exist only in debug/demo mode to append a fake transcript event while backend streaming is under development.

Modals:
- Save Recording File modal appears when leaving or stopping with unsaved audio.
- Upload confirmation modal explains that recording + transcript will be uploaded to S3 using REST API/presigned URLs.
- Modal actions must be concise and Korean is preferred for confirmation flows.

Text language:
- Korean UI text should be concise and action-oriented.
- English labels from the reference UI may be used where they are part of the demo design, for example `Meeting Rooms`, `New Room`, `Upload to S3`.

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
 │   ├─ websocket/
 │   ├─ storage/
 │   └─ errors/
 ├─ features/
 │   ├─ meetings/
 │   │   ├─ data/
 │   │   ├─ domain/
 │   │   └─ presentation/
 │   ├─ recordings/
 │   │   ├─ data/
 │   │   ├─ domain/
 │   │   └─ presentation/
 │   └─ transcription/
 │       ├─ data/
 │       ├─ domain/
 │       └─ presentation/
 └─ shared/
     ├─ widgets/
     └─ theme/
```

Rules:
- Keep widgets focused on rendering and user interaction.
- Put REST calls in data/API classes, not directly in widgets.
- Put WebSocket streaming logic in a dedicated service/repository.
- Put recorder control and file persistence in a dedicated recording service.
- Put local DB reads/writes in repositories.
- Put API DTO parsing in model classes with explicit types.
- Keep backend status strings mapped to typed Dart enums.
- Keep recording/start/stop/upload/summarize orchestration in a controller, notifier, bloc, or use case layer.

---

## Networking Rules

- Use one centralized API client for FastAPI REST calls.
- Use one centralized WebSocket client/service for realtime transcription.
- Use a separate upload method for S3 presigned URL `PUT` requests.
- Do not call AWS SDKs directly from Flutter.
- Do not attach backend auth headers to S3 presigned uploads unless the backend explicitly requires it.
- Preserve `Content-Type` when uploading to S3.
- Add request timeout and clear error mapping for REST.
- WebSocket must expose connection, recording, paused, reconnecting, failed, and closed states.
- Avoid duplicate WebSocket sessions for the same meeting.
- Keep chunk sending ordered and avoid unbounded buffering if the WebSocket is slow.
- Surface backend transcript/status events to the controller as typed events, not raw maps in widgets.
- Close streams, subscriptions, recorder handles, and timers when leaving a room.
- Do not start summary generation until final transcript is available.

---

## Error Handling

Flutter must handle:
- microphone permission denied
- recorder initialization failure
- local file save failure
- local DB write/read failure
- API server unavailable
- WebSocket connection failure
- WebSocket disconnect during recording
- backend Transcribe Streaming failure
- unsupported audio format
- S3 upload failure
- expired presigned URL
- meeting not found
- summary job already in progress
- worker not running locally, where summary status stays queued
- worker failure with `error_message`
- timeout while waiting for summary result
- local storage full or file missing

Display user-facing Korean messages, but keep internal exception names and logs developer-readable.

---

## Secrets Rules

- Do not commit API secrets, AWS keys, Firebase service account JSON, APNs keys, signing keys, or local `.env` files.
- Do not put AWS Access Key, Secret Access Key, or session token in Dart code.
- Flutter must not use AWS SDK credentials for Transcribe, Bedrock, or S3.
- Use backend WebSocket for realtime STT.
- Use backend-provided presigned URLs for S3 upload.
- Environment-specific REST and WebSocket base URLs should be configured through build flavors, `--dart-define`, or a local ignored config file.

---

## Local Run

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

Backend local run is managed in `../KB-AI-Hackerton-Backend/server`.
For an end-to-end local backend flow, run the FastAPI WebSocket/REST server and any worker process needed for summary generation.

---

## Final Principle

Flutter = meeting room workflow, recording, local files, realtime transcript UI
FastAPI = REST API, WebSocket API, presigned URL issuance
Amazon Transcribe Streaming = backend-owned realtime STT
S3 = optional post-recording asset storage through presigned URLs
LangGraph / Bedrock = backend-owned summary/minutes generation
