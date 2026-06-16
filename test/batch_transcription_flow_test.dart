import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/core/websocket/transcription_socket_client.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/meeting_api.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/batch_transcription_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_room.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_type.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/recording_asset.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/presentation/meetings_controller.dart';
import 'package:kb_ai_hackerton_frontend/features/recordings/data/audio_file_picker_service.dart';
import 'package:kb_ai_hackerton_frontend/features/recordings/data/realtime_audio_streaming_service.dart';
import 'package:kb_ai_hackerton_frontend/features/recordings/data/saved_recording_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (_) async => null,
      );

  test('uploads an audio file and stores completed batch result', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'voice-doc-batch-test',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final audioFile = File('${tempDirectory.path}/meeting.m4a');
    await audioFile.writeAsBytes(List<int>.filled(32, 1));

    final now = DateTime(2026, 6, 11);
    final room = MeetingRoom(
      localId: 'local-batch',
      meetingId: 'MTG-20260611-010',
      backendId: 'backend-batch',
      title: '배치 테스트',
      meetingType: MeetingType.small,
      status: MeetingStatus.ready,
      createdAt: now,
      updatedAt: now,
    );
    final repository = InMemoryMeetingRepository(rooms: [room]);
    final api = _FakeBatchMeetingApi();
    final controller = MeetingsController(
      repository: repository,
      api: api,
      transcriptionSocketClient: _FakeTranscriptionSocketClient(),
      audioStreamingService: _FakeRealtimeAudioStreamingService(),
      savedRecordingFileService: _FakeSavedRecordingFileService(),
      audioFilePickerService: _FakeAudioFilePickerService(
        RecordingAsset(
          fileName: 'meeting.m4a',
          filePath: audioFile.path,
          contentType: 'audio/mp4',
          durationMs: 0,
          realtimeAudioEncoding: 'batch_file',
          realtimeSampleRate: 0,
          realtimeChannels: 0,
        ),
      ),
      batchPollInterval: const Duration(milliseconds: 1),
    );
    addTearDown(controller.dispose);

    await controller.loadRooms();
    controller.selectRoom(room);
    await controller.startBatchTranscription(useSavedRecording: false);
    await _waitFor(
      () async =>
          (await repository.getRoom(room.localId))?.status ==
          MeetingStatus.completed,
    );

    final saved = await repository.getRoom(room.localId);
    expect(api.uploadedFilePath, audioFile.path);
    expect(api.uploadConfirmed, isTrue);
    expect(api.batchStatusRequested, isTrue);
    expect(saved?.recording?.audioS3Key, 'audio/backend-batch/original.m4a');
    expect(saved?.batchJobId, 'job-batch');
    expect(saved?.batchStatus, BatchTranscriptionStatus.completed);
    expect(saved?.status, MeetingStatus.completed);
    expect(saved?.summary, '배치 회의 요약');
    expect(saved?.decisions, ['배치 처리 방식을 확정합니다.']);
    expect(saved?.openIssues, ['실기기 성능 검증이 필요합니다.']);
    expect(saved?.actionItems.single['owner'], '참가자1');
    expect(saved?.pdfS3Key, 'pdf/backend-batch/minutes.pdf');
    expect(saved?.docxS3Key, 'docx/backend-batch/minutes.docx');
  });

  test('keeps queued state when start response contains an unknown status', () {
    expect(
      MeetingStatus.fromJson('running', fallback: MeetingStatus.queued),
      MeetingStatus.queued,
    );
  });

  test('maps backend batch status codes to typed states', () {
    expect(
      BatchTranscriptionStatus.fromCode(3),
      BatchTranscriptionStatus.transcribing,
    );
    expect(
      BatchTranscriptionStatus.fromCode('5'),
      BatchTranscriptionStatus.completed,
    );
    expect(BatchTranscriptionStatus.fromCode(99), isNull);
  });
}

Future<void> _waitFor(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition was not met before timeout.');
}

class _FakeBatchMeetingApi extends MeetingApi {
  String? uploadedFilePath;
  bool uploadConfirmed = false;
  bool batchStatusRequested = false;

  @override
  Future<Map<String, dynamic>> requestAudioUploadUrl(
    String backendMeetingId, {
    String fileExtension = 'm4a',
    String contentType = 'audio/mp4',
  }) async {
    return {
      'upload_url': 'https://example.com/upload',
      's3_key': 'audio/$backendMeetingId/original.$fileExtension',
      'expires_in': 900,
    };
  }

  @override
  Future<void> uploadAudioFile(
    String uploadUrl, {
    required String filePath,
    required String contentType,
  }) async {
    uploadedFilePath = filePath;
  }

  @override
  Future<Map<String, dynamic>> confirmAudioUpload(
    String backendMeetingId,
  ) async {
    uploadConfirmed = true;
    return {
      'meeting_id': backendMeetingId,
      'status': 'uploaded',
      'audio_s3_key': 'audio/$backendMeetingId/original.m4a',
      'uploaded': true,
    };
  }

  @override
  Future<Map<String, dynamic>> startMeetingPipeline(
    String backendMeetingId,
  ) async {
    if (!uploadConfirmed) {
      throw StateError('Upload must be confirmed before start.');
    }
    return {
      'meeting_id': backendMeetingId,
      'job_id': 'job-batch',
      'status': 'queued',
    };
  }

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async {
    return {'id': jobId, 'status': 'completed', 'error_message': null};
  }

  @override
  Future<Map<String, dynamic>> getBatchStatus(String backendMeetingId) async {
    batchStatusRequested = true;
    return {
      'meeting_id': backendMeetingId,
      'status': 'completed',
      'batch_status_code': 5,
      'synced': false,
      'job_id': 'job-batch',
      'job_status': 'completed',
      'job_batch_status_code': 5,
    };
  }

  @override
  Future<Map<String, dynamic>> getMeeting(String backendMeetingId) async {
    return {
      'id': backendMeetingId,
      'status': 'queued',
      'audio_s3_key': 'audio/$backendMeetingId/original.m4a',
      'transcript_s3_key': 'transcript/$backendMeetingId/transcript.txt',
    };
  }

  @override
  Future<Map<String, dynamic>> getMeetingResult(String backendMeetingId) async {
    return {
      'meeting_id': backendMeetingId,
      'status': 'completed',
      'summary': '배치 회의 요약',
      'decisions': ['배치 처리 방식을 확정합니다.'],
      'open_issues': ['실기기 성능 검증이 필요합니다.'],
      'action_items': [
        {
          'owner': '참가자1',
          'task': '실기기 테스트',
          'due_date': '금요일',
          'resolved': 'false',
        },
      ],
      'minutes_json_s3_key': 'minutes/$backendMeetingId/minutes.json',
      'minutes_markdown_s3_key': 'minutes/$backendMeetingId/minutes.md',
      'pdf_s3_key': 'pdf/$backendMeetingId/minutes.pdf',
      'docx_s3_key': 'docx/$backendMeetingId/minutes.docx',
    };
  }
}

class _FakeAudioFilePickerService extends AudioFilePickerService {
  _FakeAudioFilePickerService(this.recording);

  final RecordingAsset recording;

  @override
  Future<RecordingAsset?> pickAudioFile() async => recording;
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
