import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/core/websocket/transcription_socket_client.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/data/meeting_api.dart';
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
    expect(saved?.recording?.audioS3Key, 'audio/backend-batch/original.m4a');
    expect(saved?.batchJobId, 'job-batch');
    expect(saved?.status, MeetingStatus.completed);
    expect(saved?.summary, '배치 회의 요약');
    expect(saved?.pdfS3Key, 'pdf/backend-batch/minutes.pdf');
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
  Future<Map<String, dynamic>> startMeetingPipeline(
    String backendMeetingId,
  ) async {
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
  Future<Map<String, dynamic>> getMeeting(String backendMeetingId) async {
    return {'id': backendMeetingId, 'status': 'completed'};
  }

  @override
  Future<Map<String, dynamic>> getMeetingResult(String backendMeetingId) async {
    return {
      'meeting_id': backendMeetingId,
      'status': 'completed',
      'summary': '배치 회의 요약',
      'minutes_json_s3_key': 'minutes/$backendMeetingId/minutes.json',
      'minutes_markdown_s3_key': 'minutes/$backendMeetingId/minutes.md',
      'pdf_s3_key': 'pdf/$backendMeetingId/minutes.pdf',
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
