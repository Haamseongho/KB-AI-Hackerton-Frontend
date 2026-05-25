import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/microphone_permission_service.dart';
import '../../meetings/data/meeting_api.dart';
import '../domain/meeting_repository.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_type.dart';
import '../domain/transcript_segment.dart';

class MeetingsController extends ChangeNotifier {
  MeetingsController({
    required MeetingRepository repository,
    required MeetingApi api,
    MicrophonePermissionService? permissionService,
  }) : _repository = repository,
       _api = api,
       _permissionService = permissionService ?? MicrophonePermissionService();

  final MeetingRepository _repository;
  final MeetingApi _api;
  final MicrophonePermissionService _permissionService;

  List<MeetingRoom> rooms = const [];
  MeetingRoom? selectedRoom;
  String query = '';
  String statusMessage = 'Rooms are stored locally for quick testing.';
  String? errorMessage;
  bool isLoading = false;
  bool debugMode = true;

  Future<void> loadRooms() async {
    isLoading = true;
    notifyListeners();
    rooms = await _repository.listRooms(query: query);
    isLoading = false;
    notifyListeners();
  }

  Future<void> search(String value) async {
    query = value;
    rooms = await _repository.listRooms(query: query);
    notifyListeners();
  }

  Future<void> createRoom({
    required String title,
    required MeetingType meetingType,
    required String storageType,
    String? notes,
  }) async {
    final now = DateTime.now();
    final meetingId = _makeMeetingId(now, rooms.length + 1);
    final room = MeetingRoom(
      localId: 'local-${now.microsecondsSinceEpoch}',
      meetingId: meetingId,
      title: title.trim().isEmpty ? 'Untitled Meeting' : title.trim(),
      meetingType: meetingType,
      status: MeetingStatus.ready,
      createdAt: now,
      updatedAt: now,
      notes: notes,
    );

    await _repository.saveRoom(room);
    await loadRooms();
    selectRoom(room);

    unawaited(
      _api
          .createMeetingRoom(
            title: room.title,
            meetingType: meetingType,
            notes: notes,
          )
          .then((json) async {
            final backendId = json['id'];
            if (backendId is! String) return <String, dynamic>{};
            final updated = room.copyWith(backendId: backendId);
            await _repository.saveRoom(updated);
            rooms = await _repository.listRooms(query: query);
            if (selectedRoom?.localId == updated.localId) {
              selectedRoom = updated;
            }
            notifyListeners();
            return json;
          })
          .catchError((Object error) {
            statusMessage = 'Local room created. REST create failed.';
            errorMessage = error.toString();
            notifyListeners();
            return <String, dynamic>{};
          }),
    );
  }

  void selectRoom(MeetingRoom room) {
    selectedRoom = room;
    statusMessage = _messageFor(room.status);
    errorMessage = null;
    notifyListeners();
  }

  Future<void> startRecording() async {
    final room = selectedRoom;
    if (room == null) return;

    final granted = await _permissionService.ensureGranted();
    if (!granted) {
      errorMessage = '마이크 권한이 필요합니다.';
      notifyListeners();
      return;
    }

    final updated = room.copyWith(
      status: MeetingStatus.recording,
      updatedAt: DateTime.now(),
      streamSegmentCount: room.streamSegmentCount + 1,
      partialTranscript: null,
      streamSessionId: 'stream-${DateTime.now().microsecondsSinceEpoch}',
    );
    await _saveAndSelect(updated, 'Sending PCM audio to FastAPI.');
  }

  Future<void> pauseRecording() async {
    final room = selectedRoom;
    if (room == null) return;

    final updated = room.copyWith(
      status: MeetingStatus.paused,
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(updated, 'Paused. Press Record to open a new stream.');
  }

  Future<void> leaveRoom() async {
    final room = selectedRoom;
    if (room == null) return;

    final updated = room.copyWith(
      status: room.segments.isEmpty
          ? MeetingStatus.ready
          : MeetingStatus.transcriptionCompleted,
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(
      updated,
      'Recording and transcript are saved locally.',
    );
  }

  Future<void> appendDebugTranscript() async {
    final room = selectedRoom;
    if (room == null) return;

    final now = Duration(seconds: room.segments.length * 5 + 1);
    final segment = TranscriptSegment(
      id: 'debug-${DateTime.now().microsecondsSinceEpoch}',
      text: _debugTexts[room.segments.length % _debugTexts.length],
      startedAt: now,
      endedAt: now + const Duration(seconds: 3),
      isFinal: true,
      speaker: 'Speaker 1',
    );

    final updated = room.copyWith(
      status: room.status == MeetingStatus.paused
          ? MeetingStatus.paused
          : MeetingStatus.recording,
      segments: [...room.segments, segment],
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(updated, 'Final transcript received.');
  }

  Future<void> requestUpload() async {
    final room = selectedRoom;
    if (room == null) return;

    try {
      final backendMeetingId = room.backendId;
      if (backendMeetingId == null) {
        throw const AppException(
          'Backend meeting id is missing. Create the room while the API server is reachable before upload.',
        );
      }
      statusMessage = 'Requesting presigned upload URLs.';
      errorMessage = null;
      notifyListeners();
      await _api.requestAudioUploadUrl(backendMeetingId);
      final updated = room.copyWith(
        status: MeetingStatus.uploaded,
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(updated, 'Upload API call completed.');
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
    }
  }

  void toggleAutoScroll(bool value) {
    final room = selectedRoom;
    if (room == null) return;
    final updated = room.copyWith(autoScroll: value);
    selectedRoom = updated;
    notifyListeners();
    unawaited(_repository.saveRoom(updated));
  }

  Future<void> _saveAndSelect(MeetingRoom room, String message) async {
    final saved = await _repository.saveRoom(room);
    selectedRoom = saved;
    rooms = await _repository.listRooms(query: query);
    statusMessage = message;
    errorMessage = null;
    notifyListeners();
  }

  String _makeMeetingId(DateTime now, int ordinal) {
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'MTG-$date-${ordinal.toString().padLeft(3, '0')}';
  }

  String _messageFor(MeetingStatus status) {
    return switch (status) {
      MeetingStatus.ready => 'Ready. Press Record to stream PCM audio.',
      MeetingStatus.recording => 'Backend status: transcribing',
      MeetingStatus.paused => 'Transcription is paused.',
      MeetingStatus.transcribing => 'Backend status: transcribing',
      MeetingStatus.transcriptionCompleted => 'Transcription complete.',
      MeetingStatus.summaryQueued => 'Summary job is queued.',
      MeetingStatus.summarizing => 'Summarizing transcript.',
      MeetingStatus.completed => 'Meeting minutes are ready.',
      MeetingStatus.uploaded => 'Uploaded to S3.',
      MeetingStatus.failed => 'Processing failed.',
    };
  }

  String _userMessage(Object error) {
    if (error is AppException) return error.message;
    return '요청에 실패했습니다. 서버와 네트워크 상태를 확인해 주세요.';
  }
}

const _debugTexts = [
  '자료를 시작하겠습니다.',
  '녹음.',
  '리얼 타임 테스트.',
  '네.',
  '된 건가?',
  'Realtime transcription test event.',
];
