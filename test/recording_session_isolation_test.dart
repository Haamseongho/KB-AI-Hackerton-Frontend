import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/core/permissions/microphone_permission_service.dart';
import 'package:kb_ai_hackerton_frontend/core/websocket/transcription_socket_client.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/meeting_api.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_room.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_type.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/transcript_segment.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/transcription_event.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/presentation/meetings_controller.dart';
import 'package:kb_ai_hackerton_frontend/features/recordings/data/realtime_audio_streaming_service.dart';
import 'package:kb_ai_hackerton_frontend/features/recordings/data/saved_recording_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (_) async => null,
      );

  test(
    'background transcript events stay in the room that started recording',
    () async {
      final now = DateTime(2026, 6, 11);
      final firstRoom = MeetingRoom(
        localId: 'local-a',
        meetingId: 'MTG-20260611-001',
        backendId: 'backend-a',
        title: 'A 회의',
        meetingType: MeetingType.small,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      );
      final secondRoom = MeetingRoom(
        localId: 'local-b',
        meetingId: 'MTG-20260611-002',
        backendId: 'backend-b',
        title: 'B 회의',
        meetingType: MeetingType.small,
        status: MeetingStatus.ready,
        createdAt: now,
        updatedAt: now,
      );
      final repository = InMemoryMeetingRepository(
        rooms: [firstRoom, secondRoom],
      );
      final socket = _FakeTranscriptionSocketClient();
      final controller = MeetingsController(
        repository: repository,
        api: MeetingApi(),
        permissionService: _GrantedMicrophonePermissionService(),
        transcriptionSocketClient: socket,
        audioStreamingService: _FakeRealtimeAudioStreamingService(),
        savedRecordingFileService: _FakeSavedRecordingFileService(),
      );
      addTearDown(controller.dispose);

      await controller.loadRooms();
      controller.selectRoom(firstRoom);
      await controller.startRecording();

      controller.selectRoom(secondRoom);
      socket.emit(
        const FinalTranscriptEvent(
          segment: TranscriptSegment(
            id: 'segment-1',
            text: 'A 회의에서 녹음된 문장',
            startedAt: Duration(seconds: 1),
            endedAt: Duration(seconds: 2),
            isFinal: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final savedFirstRoom = await repository.getRoom(firstRoom.localId);
      final savedSecondRoom = await repository.getRoom(secondRoom.localId);

      expect(savedFirstRoom?.segments.single.text, 'A 회의에서 녹음된 문장');
      expect(savedSecondRoom?.segments, isEmpty);
      expect(controller.selectedRoom?.localId, secondRoom.localId);
      expect(controller.isRecordingAnotherRoom(secondRoom.localId), isTrue);
    },
  );
}

class _GrantedMicrophonePermissionService extends MicrophonePermissionService {
  @override
  Future<bool> ensureGranted() async => true;
}

class _FakeTranscriptionSocketClient extends TranscriptionSocketClient {
  final StreamController<TranscriptionEvent> _controller =
      StreamController<TranscriptionEvent>.broadcast();

  @override
  Stream<TranscriptionEvent> get events => _controller.stream;

  void emit(TranscriptionEvent event) => _controller.add(event);

  @override
  Future<void> connect({
    required String meetingId,
    int sampleRate = 16000,
    int channels = 1,
    int chunkDurationMs = 100,
    String mediaEncoding = 'pcm',
    String languageCode = 'ko-KR',
    String? vocabularyName,
  }) async {}

  @override
  void sendPcmChunk(Uint8List bytes) {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}

  @override
  void dispose() {
    _controller.close();
  }
}

class _FakeRealtimeAudioStreamingService extends RealtimeAudioStreamingService {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();

  @override
  Future<Stream<Uint8List>> startPcmStream({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    return _controller.stream;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeSavedRecordingFileService extends SavedRecordingFileService {
  @override
  Future<void> startOrResume({
    required String meetingId,
    required String title,
  }) async {}

  @override
  Future<void> dispose() async {}
}
