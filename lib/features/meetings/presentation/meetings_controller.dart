import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/microphone_permission_service.dart';
import '../../../core/websocket/transcription_socket_client.dart';
import '../../recordings/data/realtime_audio_streaming_service.dart';
import '../../recordings/data/saved_recording_file_service.dart';
import '../../transcription/data/transcript_file_service.dart';
import '../../meetings/data/meeting_api.dart';
import '../domain/meeting_repository.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_type.dart';
import '../domain/recording_asset.dart';
import '../domain/transcript_segment.dart';
import '../domain/transcription_event.dart';

/// 회의방 화면의 녹음, 실시간 STT, 회의록 생성 흐름을 조율하는 컨트롤러입니다.
///
/// Widget은 화면 렌더링과 사용자 입력만 담당하고, backend meeting 생성,
/// WebSocket 연결, PCM chunk 전송, transcript 누적, 파일 저장, 회의록 생성 요청은
/// 이 컨트롤러가 서비스 계층에 위임합니다.
class MeetingsController extends ChangeNotifier {
  MeetingsController({
    required MeetingRepository repository,
    required MeetingApi api,
    MicrophonePermissionService? permissionService,
    TranscriptionSocketClient? transcriptionSocketClient,
    RealtimeAudioStreamingService? audioStreamingService,
    SavedRecordingFileService? savedRecordingFileService,
    TranscriptFileService? transcriptFileService,
  }) : _repository = repository,
       _api = api,
       _permissionService = permissionService ?? MicrophonePermissionService(),
       _transcriptionSocketClient =
           transcriptionSocketClient ?? TranscriptionSocketClient(),
       _audioStreamingService =
           audioStreamingService ?? RealtimeAudioStreamingService(),
       _savedRecordingFileService =
           savedRecordingFileService ?? SavedRecordingFileService(),
       _transcriptFileService =
           transcriptFileService ?? TranscriptFileService();

  final MeetingRepository _repository;
  final MeetingApi _api;
  final MicrophonePermissionService _permissionService;
  final TranscriptionSocketClient _transcriptionSocketClient;
  final RealtimeAudioStreamingService _audioStreamingService;
  final SavedRecordingFileService _savedRecordingFileService;
  final TranscriptFileService _transcriptFileService;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<TranscriptionEvent>? _transcriptionSubscription;
  DateTime? _streamStartedAt;
  final Map<String, Future<String>> _backendCreateFutures = {};

  List<MeetingRoom> rooms = const [];
  MeetingRoom? selectedRoom;
  String query = '';
  String statusMessage = 'Rooms are stored locally for quick testing.';
  String? errorMessage;
  bool isLoading = false;
  bool debugMode = true;

  /// 저장된 회의방 목록을 현재 검색어 기준으로 다시 불러옵니다.
  Future<void> loadRooms() async {
    isLoading = true;
    notifyListeners();
    rooms = await _repository.listRooms(query: query);
    isLoading = false;
    notifyListeners();
  }

  /// 회의방 제목 또는 meeting_id 검색어를 적용합니다.
  Future<void> search(String value) async {
    query = value;
    rooms = await _repository.listRooms(query: query);
    notifyListeners();
  }

  /// 로컬 회의방을 만들고, 가능한 경우 즉시 backend meeting도 생성합니다.
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
      _ensureBackendMeeting(room).catchError((Object error) {
        statusMessage = 'Local room created. REST create failed.';
        errorMessage = error.toString();
        notifyListeners();
        return '';
      }),
    );
  }

  /// 목록이나 상세 화면에서 선택한 회의방을 현재 작업 대상으로 설정합니다.
  void selectRoom(MeetingRoom room) {
    selectedRoom = room;
    statusMessage = _messageFor(room.status);
    errorMessage = null;
    notifyListeners();
  }

  /// 마이크 권한을 확인한 뒤 backend WebSocket에 PCM 스트림을 전송합니다.
  Future<void> startRecording() async {
    final room = selectedRoom;
    if (room == null) return;

    final granted = await _permissionService.ensureGranted();
    if (!granted) {
      errorMessage = '마이크 권한이 필요합니다.';
      notifyListeners();
      return;
    }

    await _stopRealtimeStream(controlType: 'stop');

    try {
      final backendMeetingId = await _ensureBackendMeeting(room);
      _listenToTranscriptionEvents();
      await _transcriptionSocketClient.connect(meetingId: backendMeetingId);
      _streamStartedAt = DateTime.now();

      final audioStream = await _audioStreamingService.startPcmStream();
      _audioSubscription = audioStream.listen(
        _transcriptionSocketClient.sendPcmChunk,
        onError: (Object error) {
          errorMessage = _userMessage(error);
          notifyListeners();
        },
        cancelOnError: true,
      );
    } catch (error) {
      await _stopRealtimeStream(controlType: 'stop');
      final failed = (selectedRoom ?? room).copyWith(
        status: MeetingStatus.paused,
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(failed, 'Realtime stream failed.');
      errorMessage = _userMessage(error);
      notifyListeners();
      return;
    }

    final activeRoom = selectedRoom ?? room;
    final savedRecordingWarning = await _startSavedRecording(activeRoom);
    final updated = activeRoom.copyWith(
      status: MeetingStatus.recording,
      updatedAt: DateTime.now(),
      streamSegmentCount: activeRoom.streamSegmentCount + 1,
      partialTranscript: null,
      streamSessionId: 'stream-${DateTime.now().microsecondsSinceEpoch}',
    );
    await _saveAndSelect(
      updated,
      savedRecordingWarning ?? 'Sending PCM audio to FastAPI.',
    );
  }

  /// 현재 WebSocket/오디오 스트림을 닫고 transcript 누적 상태는 보존합니다.
  Future<void> pauseRecording() async {
    final room = selectedRoom;
    if (room == null) return;

    await _stopRealtimeStream(controlType: 'pause');
    await _pauseSavedRecording();

    final updated = room.copyWith(
      status: MeetingStatus.paused,
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(updated, 'Paused. Press Record to open a new stream.');
  }

  /// 회의방을 나가며 realtime stream을 종료하고 transcript 파일을 로컬에 저장합니다.
  Future<void> leaveRoom() async {
    final room = selectedRoom;
    if (room == null) return;

    await _stopRealtimeStream(controlType: 'stop');
    final recordingAsset = await _stopSavedRecording(room);

    final transcriptFilePath = await _transcriptFileService.saveTranscript(
      meetingId: room.meetingId,
      title: room.title,
      segments: room.segments,
    );

    final updated = room.copyWith(
      status: room.segments.isEmpty
          ? MeetingStatus.ready
          : MeetingStatus.transcriptionCompleted,
      recording: recordingAsset ?? room.recording ?? _recordingAssetFor(room),
      transcriptFilePath: transcriptFilePath,
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(
      updated,
      'Recording and transcript are saved locally.',
    );
  }

  /// 백엔드 연동 전에도 UI 흐름을 검증할 수 있도록 final transcript를 추가합니다.
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

  /// 최종 transcript segment를 backend `/minutes-from-realtime`로 보내 회의록을 생성합니다.
  Future<void> generateMinutesFromRealtime() async {
    final room = selectedRoom;
    if (room == null) return;

    try {
      final backendMeetingId = await _ensureBackendMeeting(room);
      final generating = room.copyWith(
        backendId: backendMeetingId,
        status: MeetingStatus.generatingMinutes,
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(
        generating,
        'Requesting realtime minutes generation.',
      );
      errorMessage = null;
      notifyListeners();
      final segments = generating.segments.isEmpty
          ? null
          : generating.segments
                .map(
                  (segment) => {
                    'speaker_label': segment.speaker,
                    'transcript_text': segment.text,
                  },
                )
                .toList(growable: false);
      final result = await _api.createMinutesFromRealtime(
        backendMeetingId,
        segments: segments,
      );
      final updated = generating.copyWith(
        status: MeetingStatus.fromJson(result['status'] as String?),
        title: result['title'] as String?,
        summary: result['summary'] as String?,
        minutesJsonS3Key: result['minutes_json_s3_key'] as String?,
        minutesMarkdownS3Key: result['minutes_markdown_s3_key'] as String?,
        pdfS3Key: result['pdf_s3_key'] as String?,
        uploadedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(updated, 'Realtime minutes generation completed.');
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
    }
  }

  /// 기존 UI 콜백과의 호환을 위한 별칭입니다. 실제 동작은 회의록 생성입니다.
  Future<void> requestUpload() => generateMinutesFromRealtime();

  /// transcript 패널의 자동 스크롤 상태를 저장합니다.
  void toggleAutoScroll(bool value) {
    final room = selectedRoom;
    if (room == null) return;
    final updated = room.copyWith(autoScroll: value);
    selectedRoom = updated;
    notifyListeners();
    unawaited(_repository.saveRoom(updated));
  }

  /// 로컬 저장소에 room을 저장하고 현재 선택 상태와 목록을 동기화합니다.
  Future<void> _saveAndSelect(MeetingRoom room, String message) async {
    final saved = await _repository.saveRoom(room);
    selectedRoom = saved;
    rooms = await _repository.listRooms(query: query);
    statusMessage = message;
    errorMessage = null;
    notifyListeners();
  }

  /// WebSocket/회의록 API가 사용할 backend UUID를 보장합니다.
  Future<String> _ensureBackendMeeting(MeetingRoom room) async {
    if (room.backendId != null) return room.backendId!;
    final pending = _backendCreateFutures[room.localId];
    if (pending != null) return pending;

    final future = () async {
      final json = await _api.createMeetingRoom(
        title: room.title,
        meetingType: room.meetingType,
        notes: room.notes,
      );
      final backendId = json['id'];
      if (backendId is! String || backendId.isEmpty) {
        throw const AppException('Backend meeting id is missing in response.');
      }

      final updated = room.copyWith(
        backendId: backendId,
        updatedAt: DateTime.now(),
      );
      await _repository.saveRoom(updated);
      rooms = await _repository.listRooms(query: query);
      if (selectedRoom?.localId == room.localId) {
        selectedRoom = updated;
      }
      notifyListeners();
      return backendId;
    }();

    _backendCreateFutures[room.localId] = future;
    try {
      return await future;
    } finally {
      _backendCreateFutures.remove(room.localId);
    }
  }

  /// WebSocket 이벤트 스트림을 controller 상태 변경으로 변환합니다.
  void _listenToTranscriptionEvents() {
    unawaited(_transcriptionSubscription?.cancel());
    _transcriptionSubscription = _transcriptionSocketClient.events.listen(
      _handleTranscriptionEvent,
    );
  }

  /// backend에서 받은 status/partial/final/error 이벤트를 UI 모델에 반영합니다.
  void _handleTranscriptionEvent(TranscriptionEvent event) {
    final room = selectedRoom;
    if (room == null) return;

    switch (event) {
      case TranscriptionStatusEvent():
        statusMessage = event.message;
        notifyListeners();
      case PartialTranscriptEvent():
        final updated = room.copyWith(
          partialTranscript: event.text,
          updatedAt: DateTime.now(),
        );
        unawaited(_saveAndSelect(updated, event.text));
      case FinalTranscriptEvent():
        final segment = _withElapsedFallback(event.segment);
        final updated = room.copyWith(
          segments: [...room.segments, segment],
          updatedAt: DateTime.now(),
          clearPartialTranscript: true,
        );
        unawaited(_saveAndSelect(updated, 'Final transcript received.'));
      case TranscriptionErrorEvent():
        errorMessage = event.message;
        notifyListeners();
    }
  }

  /// backend가 timestamp를 주지 않는 경우 앱 기준 경과 시간을 보완합니다.
  TranscriptSegment _withElapsedFallback(TranscriptSegment segment) {
    if (segment.startedAt != Duration.zero ||
        segment.endedAt != Duration.zero) {
      return segment;
    }

    final elapsed = _streamStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_streamStartedAt!);
    return TranscriptSegment(
      id: segment.id,
      text: segment.text,
      startedAt: elapsed,
      endedAt: elapsed,
      isFinal: segment.isFinal,
      speaker: segment.speaker ?? 'Speaker 1',
    );
  }

  /// 현재 MVP에서 녹음 스트림 메타데이터를 로컬 recording asset 형태로 남깁니다.
  RecordingAsset _recordingAssetFor(MeetingRoom room) {
    return RecordingAsset(
      fileName: '${room.meetingId}_realtime_stream.pcm',
      filePath: 'local://realtime-stream/${room.meetingId}.pcm',
      contentType: 'audio/pcm',
      durationMs: _transcriptDuration(room).inMilliseconds,
      realtimeAudioEncoding: 'pcm',
      realtimeSampleRate: 16000,
      realtimeChannels: 1,
    );
  }

  /// 저장/업로드용 encoded 녹음 파일 생성을 시작하거나 재개합니다.
  Future<String?> _startSavedRecording(MeetingRoom room) async {
    try {
      await _savedRecordingFileService.startOrResume(
        meetingId: room.meetingId,
        title: room.title,
      );
      return null;
    } catch (error) {
      return 'PCM streaming is active. Saved recording file failed: $error';
    }
  }

  /// 저장/업로드용 encoded 녹음 파일을 일시정지합니다.
  Future<void> _pauseSavedRecording() async {
    try {
      await _savedRecordingFileService.pause();
    } catch (error) {
      errorMessage = '녹음 파일 일시정지에 실패했습니다: $error';
      notifyListeners();
    }
  }

  /// 저장/업로드용 encoded 녹음 파일을 종료하고 metadata를 반환합니다.
  Future<RecordingAsset?> _stopSavedRecording(MeetingRoom room) async {
    try {
      return _savedRecordingFileService.stop(
        meetingId: room.meetingId,
        title: room.title,
      );
    } catch (error) {
      errorMessage = '녹음 파일 저장에 실패했습니다: $error';
      notifyListeners();
      return null;
    }
  }

  /// transcript segment 중 가장 마지막 종료 시각을 회의 길이로 사용합니다.
  Duration _transcriptDuration(MeetingRoom room) {
    if (room.segments.isEmpty) return Duration.zero;
    return room.segments
        .map((segment) => segment.endedAt)
        .reduce((a, b) => a > b ? a : b);
  }

  /// 오디오 스트림과 WebSocket을 같은 생명주기로 정리합니다.
  Future<void> _stopRealtimeStream({required String controlType}) async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _audioStreamingService.stop();

    if (controlType == 'pause') {
      _transcriptionSocketClient.pause();
    } else {
      await _transcriptionSocketClient.stop();
    }
    await _transcriptionSocketClient.close();
    await _transcriptionSubscription?.cancel();
    _transcriptionSubscription = null;
    _streamStartedAt = null;
  }

  /// 로컬 표시용 meeting_id를 날짜 기반으로 생성합니다.
  String _makeMeetingId(DateTime now, int ordinal) {
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'MTG-$date-${ordinal.toString().padLeft(3, '0')}';
  }

  /// 상태 enum을 사용자에게 보여줄 짧은 안내 문구로 변환합니다.
  String _messageFor(MeetingStatus status) {
    return switch (status) {
      MeetingStatus.ready => 'Ready. Press Record to stream PCM audio.',
      MeetingStatus.created => 'Meeting is created.',
      MeetingStatus.uploadUrlIssued => 'Upload URL has been issued.',
      MeetingStatus.uploaded => 'Uploaded to S3.',
      MeetingStatus.queued => 'Meeting job is queued.',
      MeetingStatus.orchestrationStarting => 'Workflow is starting.',
      MeetingStatus.orchestrationStarted => 'Workflow has started.',
      MeetingStatus.recording => 'Backend status: transcribing',
      MeetingStatus.paused => 'Transcription is paused.',
      MeetingStatus.transcribing => 'Backend status: transcribing',
      MeetingStatus.transcriptionCompleted => 'Transcription complete.',
      MeetingStatus.summaryQueued => 'Summary job is queued.',
      MeetingStatus.summarizing => 'Summarizing transcript.',
      MeetingStatus.generatingMinutes => 'Generating meeting minutes.',
      MeetingStatus.completed => 'Meeting minutes are ready.',
      MeetingStatus.failed => 'Processing failed.',
    };
  }

  /// 개발자용 예외를 사용자에게 보여줄 한국어 메시지로 변환합니다.
  String _userMessage(Object error) {
    if (error is AppException) return error.message;
    return '요청에 실패했습니다. 서버와 네트워크 상태를 확인해 주세요.';
  }

  @override
  void dispose() {
    unawaited(_audioSubscription?.cancel());
    unawaited(_transcriptionSubscription?.cancel());
    unawaited(_audioStreamingService.dispose());
    unawaited(_savedRecordingFileService.dispose());
    _transcriptionSocketClient.dispose();
    super.dispose();
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
