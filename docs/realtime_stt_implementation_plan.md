# Realtime STT Flutter Implementation Plan

## Scope

This document tracks the Flutter migration from batch S3 upload/transcribe flow to realtime meeting-room STT.

Current first implementation slice:
- Split the previous single-file app into `app`, `core`, and `features` folders.
- Add typed meeting, recording, transcript, and WebSocket state models.
- Add REST/WebSocket configuration through `API_BASE_URL` and `WS_BASE_URL`.
- Add iOS/Android microphone permission declarations.
- Add runtime microphone permission service.
- Build the Vercel web frontend-inspired meeting rooms and room detail UI.
- Keep actual PCM streaming, recorder persistence, and local DB as replaceable service/repository boundaries.

Out of scope for this first slice:
- Real microphone PCM chunk streaming.
- Real SQLite schema migration.
- Real WebSocket server integration test.
- Real S3 upload completion flow.
- Real LangGraph / Bedrock summary result rendering.

## Next Implementation Slices

1. Recorder integration
   - Use `record` to capture microphone audio.
   - Confirm whether the package can provide realtime PCM stream and saved file simultaneously on iOS/Android.
   - If not, use separate capture paths: PCM stream for STT, encoded file for local playback/upload.

2. WebSocket integration
   - Wire `TranscriptionSocketClient` to backend endpoint.
   - Send `start` JSON control event.
   - Send ordered PCM chunks.
   - Parse typed status, partial transcript, final transcript, and error events.
   - Handle pause as either control event or stream close + new segment based on backend behavior.

3. Local DB integration
   - Replace in-memory repository with SQLite repository.
   - Persist meetings, recordings, transcript segments, stream sessions, and upload metadata.
   - Add search by title, meeting_id, date, status, and upload state.

4. REST upload and summary
   - Request presigned upload URLs for recording and transcript.
   - Upload assets with `PUT`.
   - Mark upload complete.
   - Request summary/minutes generation.
   - Fetch and render result.

## Platform Permission Checklist

Android:
- `RECORD_AUDIO`
- `INTERNET`
- `FOREGROUND_SERVICE_MICROPHONE` may be needed if background/foreground-service recording is added later.

iOS:
- `NSMicrophoneUsageDescription`
- `NSLocalNetworkUsageDescription` is useful for local FastAPI/WebSocket testing on LAN devices.
