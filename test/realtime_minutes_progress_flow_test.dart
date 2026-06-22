import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/core/websocket/transcription_socket_client.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/meeting_api.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_room.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_type.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/transcript_segment.dart';
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

  test('polls realtime minutes progress and stores completed result', () async {
    final now = DateTime(2026, 6, 22);
    final room = MeetingRoom(
      localId: 'local-realtime',
      meetingId: 'MTG-20260622-001',
      backendId: 'backend-realtime',
      title: '실시간 회의록 테스트',
      meetingType: MeetingType.small,
      status: MeetingStatus.transcriptionCompleted,
      createdAt: now,
      updatedAt: now,
      segments: const [
        TranscriptSegment(
          id: 'segment-1',
          text: '오늘은 실시간 회의록 진행률을 확인합니다.',
          startedAt: Duration(seconds: 1),
          endedAt: Duration(seconds: 3),
          isFinal: true,
        ),
      ],
    );
    final repository = InMemoryMeetingRepository(rooms: [room]);
    final api = _FakeRealtimeMinutesApi();
    final controller = MeetingsController(
      repository: repository,
      api: api,
      transcriptionSocketClient: _FakeTranscriptionSocketClient(),
      audioStreamingService: _FakeRealtimeAudioStreamingService(),
      savedRecordingFileService: _FakeSavedRecordingFileService(),
      realtimeMinutesPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await controller.loadRooms();
    controller.selectRoom(room);
    await controller.generateMinutesFromRealtime();

    await _waitFor(
      () async =>
          (await repository.getRoom(
            room.localId,
          ))?.realtimeMinutesProgress?.completed ==
          true,
    );

    final saved = await repository.getRoom(room.localId);
    expect(api.started, isTrue);
    expect(api.progressRequests, greaterThanOrEqualTo(1));
    expect(saved?.status, MeetingStatus.uploaded);
    expect(saved?.realtimeMinutesProgress?.percent, 100);
    expect(saved?.summary, '실시간 회의 요약');
    expect(saved?.actionItems.single.task, '진행률 표시 확인');
    expect(saved?.pdfS3Key, 'pdf/backend-realtime/minutes.pdf');
    expect(saved?.docxS3Key, 'docx/backend-realtime/minutes.docx');
  });
}

Future<void> _waitFor(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 80; attempt += 1) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before timeout.');
}

class _FakeRealtimeMinutesApi extends MeetingApi {
  bool started = false;
  int progressRequests = 0;

  @override
  Future<Map<String, dynamic>> startMinutesFromRealtime(
    String backendMeetingId, {
    List<Map<String, Object?>>? segments,
  }) async {
    started = true;
    expect(segments?.single['transcript_text'], contains('진행률'));
    return {
      'meeting_id': backendMeetingId,
      'status': 'summarizing',
      'realtime_status_code': 5,
      'progress_percent': 0,
      'progress_step': 'requested',
      'progress_message': '회의록 생성을 요청했습니다.',
    };
  }

  @override
  Future<Map<String, dynamic>> getRealtimeProgress(
    String backendMeetingId,
  ) async {
    progressRequests += 1;
    if (progressRequests == 1) {
      return {
        'meeting_id': backendMeetingId,
        'status': 'summarizing',
        'realtime_status_code': 5,
        'progress_percent': 45,
        'progress_step': 'llm_generating_minutes',
        'progress_message': 'LLM이 회의 요약과 액션 아이템을 생성하고 있습니다.',
        'completed': false,
        'failed': false,
      };
    }
    return {
      'meeting_id': backendMeetingId,
      'status': 'completed',
      'realtime_status_code': 6,
      'progress_percent': 100,
      'progress_step': 'completed',
      'progress_message': '회의록 생성이 완료되었습니다.',
      'completed': true,
      'failed': false,
    };
  }

  @override
  Future<Map<String, dynamic>> getMeetingResult(String backendMeetingId) async {
    return {
      'meeting_id': backendMeetingId,
      'status': 'completed',
      'summary': '실시간 회의 요약',
      'decisions': ['진행률을 표시합니다.'],
      'open_issues': <String>[],
      'action_items': [
        {
          'owner': '담당자',
          'task': '진행률 표시 확인',
          'due_date': '내일',
          'due_date_resolved': '2026-06-23',
        },
      ],
      'minutes_json_s3_key': 'minutes/$backendMeetingId/minutes.json',
      'minutes_markdown_s3_key': 'minutes/$backendMeetingId/minutes.md',
      'pdf_s3_key': 'pdf/$backendMeetingId/minutes.pdf',
      'docx_s3_key': 'docx/$backendMeetingId/minutes.docx',
    };
  }

  @override
  Future<Map<String, dynamic>> getMeetingActionItems(
    String backendMeetingId,
  ) async {
    return {
      'meeting_id': backendMeetingId,
      'status': 'completed',
      'action_items': [
        {
          'owner': '담당자',
          'task': '진행률 표시 확인',
          'due_date': '내일',
          'due_date_resolved': '2026-06-23',
        },
      ],
    };
  }
}

class _FakeTranscriptionSocketClient extends TranscriptionSocketClient {
  @override
  Future<void> close() async {}

  @override
  void dispose() {}
}

class _FakeRealtimeAudioStreamingService extends RealtimeAudioStreamingService {
  @override
  Future<Stream<Uint8List>> startPcmStream({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    return const Stream<Uint8List>.empty();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeSavedRecordingFileService extends SavedRecordingFileService {
  @override
  Future<void> dispose() async {}
}
