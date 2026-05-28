# Realtime STT Flutter Implementation Plan

## Scope

This document tracks the Flutter migration from batch S3 upload/transcribe flow to realtime meeting-room STT.

## Current Backend Compatibility

As of 2026-05-26, `../KB-AI-Hackerton-Backend` `dev` exposes both batch and realtime contracts.

Batch REST contract:
- `POST /meetings`
- `POST /meetings/{meeting_id}/upload-url`
- `POST /meetings/{meeting_id}/start`
- `GET /meetings/{meeting_id}`
- `GET /meetings/{meeting_id}/result`
- `GET /jobs/{job_id}`

Realtime contract:
- `WS /ws/meetings/{meeting_id}/transcribe`
- `POST /meetings/{meeting_id}/minutes-from-realtime`

WebSocket client start/resume payload:

```json
{
  "type": "start",
  "language_code": "ko-KR",
  "media_encoding": "pcm",
  "sample_rate": 16000
}
```

WebSocket server events:
- `status`
- `transcript.partial`
- `transcript.final`
- `error`

Frontend implications:
- Keep realtime STT UI and WebSocket client behind a service boundary while actual recorder PCM streaming is wired.
- REST calls must use backend UUID `id`, not the local display ID such as `MTG-20260521-006`.
- `meeting_type` values sent to backend must be `one_on_one`, `small`, `medium`, or `unknown`.
- Current `/upload-url` accepts one audio asset only: `file_extension` and `content_type`.
- Batch summary/minutes starts through `/meetings/{meeting_id}/start`.
- Realtime summary/minutes starts through `/meetings/{meeting_id}/minutes-from-realtime`.

Implemented slices:
- Split the previous single-file app into `app`, `core`, and `features` folders.
- Add typed meeting, recording, transcript, and WebSocket state models.
- Add REST/WebSocket configuration through `API_BASE_URL` and `WS_BASE_URL`.
- Add iOS/Android microphone permission declarations.
- Add runtime microphone permission service.
- Build the Vercel web frontend-inspired meeting rooms and room detail UI.
- Open realtime STT WebSocket with backend UUID and send 16 kHz mono PCM chunks.
- Parse backend `status`, `transcript.partial`, `transcript.final`, and `error` events into typed Dart events.
- Pause/stop the realtime stream by closing audio and WebSocket resources.
- Generate minutes through `POST /meetings/{meeting_id}/minutes-from-realtime`.
- Store returned minutes metadata: `minutes_json_s3_key`, `minutes_markdown_s3_key`, and `pdf_s3_key`.
- Match the backend mobile mockup's local minutes flow state: `uploading` while requesting minutes and `uploaded` after S3 minutes artifacts are returned.
- Save final transcript text to a local txt file when leaving a room.
- Best-effort save an encoded `m4a` recording file for playback/upload while realtime PCM streaming is active.

Remaining out of scope:
- Real SQLite schema migration.
- Real WebSocket server integration test on device/emulator.
- Real S3 upload completion flow for recording assets.
- Platform confirmation that simultaneous PCM streaming and encoded file recording is stable on all target iOS/Android devices.

## Mobile Mockup Parity Check

Reference:
`../KB-AI-Hackerton-Backend/frontend/voice-doc-mobile-mockup/`

The mockup now contains executable test logic, not only static UI. Flutter should mirror these behavior points:

- Create the backend meeting before realtime streaming starts. If a local room has no backend UUID, call `POST /meetings` and store response `id` as `backendId`.
- Open `WS /ws/meetings/{backendId}/transcribe` with the backend UUID, not the display meeting ID.
- Send WebSocket start payload with only the current backend schema fields: `type`, `language_code`, `media_encoding`, and `sample_rate`.
- Capture microphone audio as 16 kHz mono signed 16-bit little-endian PCM. The web mockup uses `AudioContext`, downsampling, and `DataView.setInt16(..., true)`.
- Flutter equivalent should use `record` streaming with `RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1, echoCancel: true, noiseSuppress: true, autoGain: true)` if supported on the target platform.
- Pause behavior in the mockup sends `pause`, closes the socket, and starts a new realtime stream when Record is pressed again.
- Stop/save behavior sends `stop`, closes audio resources, and saves transcript text locally.
- Store realtime minutes result metadata returned from `/minutes-from-realtime`: `minutes_json_s3_key`, `minutes_markdown_s3_key`, and `pdf_s3_key`.
- Keep a debug-only test event path for UI validation while real microphone streaming is incomplete.
- Add a local `uploading` or `generating` UI state so minutes generation is visually distinct from completed/uploaded.

## Next Implementation Slices

1. Encoded recording file persistence
   - Current implementation starts a second `AudioRecorder` with `aacLc`/`m4a` as best-effort.
   - Test on Android emulator, Android physical device, iOS simulator, and iOS physical device.
   - If simultaneous capture is unstable, keep PCM streaming for realtime STT and disable file recording with a clear UI warning.
   - Confirm saved `recording_file_path`, `recording_content_type`, `recording_duration_ms`, and realtime audio format metadata in the local repository.

2. Local DB integration
   - Replace in-memory repository with SQLite repository.
   - Persist meetings, recordings, transcript segments, stream sessions, and upload metadata.
   - Add search by title, meeting_id, date, status, and upload state.

3. REST upload and result rendering
   - Request presigned upload URL for the saved recording asset.
   - Upload the recording file with `PUT`.
   - Start the batch pipeline through `/meetings/{meeting_id}/start` only when using saved-audio upload flow.
   - Fetch and render `/meetings/{meeting_id}/result`, including summary, decisions, action items, markdown key, and PDF key.

4. Device integration test
   - Run backend locally and launch Flutter with `API_BASE_URL` / `WS_BASE_URL`.
   - Validate Android emulator URL `10.0.2.2` and iOS simulator URL `localhost`.
   - For EC2 dev over plain HTTP/Nginx port 80, launch Flutter with `API_BASE_URL=http://<ec2-host>` and `WS_BASE_URL=ws://<ec2-host>`.
   - For EC2 behind TLS, use `https://<domain>` and `wss://<domain>`.
   - Verify microphone permission, WebSocket open, PCM chunks, partial/final transcript rendering, and `/minutes-from-realtime` response handling.

## Platform Permission Checklist

Android:
- `RECORD_AUDIO`
- `INTERNET`
- `FOREGROUND_SERVICE_MICROPHONE` may be needed if background/foreground-service recording is added later.

iOS:
- `NSMicrophoneUsageDescription`
- `NSLocalNetworkUsageDescription` is useful for local FastAPI/WebSocket testing on LAN devices.
