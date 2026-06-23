import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/microphone_permission_service.dart';
import '../../../core/websocket/transcription_socket_client.dart';
import '../../recordings/data/realtime_audio_streaming_service.dart';
import '../../recordings/data/audio_file_picker_service.dart';
import '../../recordings/data/saved_recording_file_service.dart';
import '../../transcription/data/transcript_download_service.dart';
import '../../transcription/data/transcript_file_service.dart';
import '../../meetings/data/calendar_event_service.dart';
import '../../meetings/data/meeting_api.dart';
import '../../meetings/data/pdf_download_service.dart';
import '../domain/action_item.dart';
import '../domain/batch_transcription_status.dart';
import '../domain/meeting_repository.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_type.dart';
import '../domain/meeting_workflow.dart';
import '../domain/realtime_minutes_progress.dart';
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
    AudioFilePickerService? audioFilePickerService,
    TranscriptFileService? transcriptFileService,
    TranscriptDownloadService? transcriptDownloadService,
    PdfDownloadService? pdfDownloadService,
    CalendarEventService? calendarEventService,
    Duration batchPollInterval = const Duration(seconds: 10),
    Duration realtimeMinutesPollInterval = const Duration(milliseconds: 1500),
  }) : _repository = repository,
       _api = api,
       _permissionService = permissionService ?? MicrophonePermissionService(),
       _transcriptionSocketClient =
           transcriptionSocketClient ?? TranscriptionSocketClient(),
       _audioStreamingService =
           audioStreamingService ?? RealtimeAudioStreamingService(),
       _savedRecordingFileService =
           savedRecordingFileService ?? SavedRecordingFileService(),
       _audioFilePickerService =
           audioFilePickerService ?? AudioFilePickerService(),
       _transcriptFileService =
           transcriptFileService ?? TranscriptFileService(),
       _transcriptDownloadService =
           transcriptDownloadService ?? TranscriptDownloadService(),
       _pdfDownloadService = pdfDownloadService ?? PdfDownloadService(),
       _calendarEventService = calendarEventService ?? CalendarEventService(),
       _batchPollInterval = batchPollInterval,
       _realtimeMinutesPollInterval = realtimeMinutesPollInterval;

  final MeetingRepository _repository;
  final MeetingApi _api;
  final MicrophonePermissionService _permissionService;
  final TranscriptionSocketClient _transcriptionSocketClient;
  final RealtimeAudioStreamingService _audioStreamingService;
  final SavedRecordingFileService _savedRecordingFileService;
  final AudioFilePickerService _audioFilePickerService;
  final TranscriptFileService _transcriptFileService;
  final TranscriptDownloadService _transcriptDownloadService;
  final PdfDownloadService _pdfDownloadService;
  final CalendarEventService _calendarEventService;
  final Duration _batchPollInterval;
  final Duration _realtimeMinutesPollInterval;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<TranscriptionEvent>? _transcriptionSubscription;
  DateTime? _streamStartedAt;
  String? _activeRecordingLocalId;
  Future<void> _transcriptionEventQueue = Future.value();
  final Map<String, Future<String>> _backendCreateFutures = {};
  final Set<String> _deletedLocalIds = {};
  final Map<String, Timer> _batchPollTimers = {};
  final Set<String> _batchPollingLocalIds = {};
  final Map<String, Timer> _realtimeMinutesPollTimers = {};
  final Set<String> _realtimeMinutesPollingLocalIds = {};

  List<MeetingRoom> rooms = const [];
  MeetingRoom? selectedRoom;
  String query = '';
  String statusMessage = '회의방은 로컬에 저장됩니다.';
  String? errorMessage;
  bool isLoading = false;
  bool isDownloadingPdf = false;
  bool isDownloadingDocx = false;
  bool isDownloadingTranscript = false;
  bool isRefreshingActionItems = false;
  bool isAddingCalendarEvent = false;
  bool isStartingBatch = false;
  bool debugMode = true;

  String? get activeRecordingLocalId => _activeRecordingLocalId;

  bool isRecordingAnotherRoom(String localId) {
    final activeLocalId = _activeRecordingLocalId;
    return activeLocalId != null && activeLocalId != localId;
  }

  String? get activeRecordingRoomTitle {
    final activeLocalId = _activeRecordingLocalId;
    if (activeLocalId == null) return null;
    for (final room in rooms) {
      if (room.localId == activeLocalId) return room.title;
    }
    return null;
  }

  /// 저장된 회의방 목록을 현재 검색어 기준으로 다시 불러옵니다.
  Future<void> loadRooms() async {
    isLoading = true;
    notifyListeners();
    rooms = await _repository.listRooms(query: query);
    isLoading = false;
    notifyListeners();
    for (final room in rooms) {
      if (room.batchJobId != null && _isBatchProcessing(room.status)) {
        _scheduleBatchPoll(room.localId, immediate: true);
      }
      if (_isRealtimeMinutesProcessing(room)) {
        _scheduleRealtimeMinutesPoll(room.localId, immediate: true);
      }
    }
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
    required String workflowType,
    String? notes,
  }) async {
    final now = DateTime.now();
    final meetingId = _makeMeetingId(now, rooms.length + 1);
    final room = MeetingRoom(
      localId: 'local-${now.microsecondsSinceEpoch}',
      meetingId: meetingId,
      title: title.trim().isEmpty ? '제목 없는 회의' : title.trim(),
      meetingType: meetingType,
      status: MeetingStatus.ready,
      createdAt: now,
      updatedAt: now,
      workflow: workflowType == MeetingWorkflow.batch.value
          ? MeetingWorkflow.batch
          : MeetingWorkflow.realtime,
      notes: notes,
    );

    await _repository.saveRoom(room);
    await loadRooms();
    selectRoom(room);

    unawaited(
      _ensureBackendMeeting(room).catchError((Object error) {
        statusMessage = '로컬 회의방은 생성됐지만 REST 생성 요청은 실패했습니다.';
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

  /// 백엔드 transcript/S3 산출물과 기기의 회의 데이터 및 파일을 함께 삭제합니다.
  Future<void> deleteRoom(MeetingRoom room) async {
    if (_isActive(room.status)) {
      throw const AppException('녹음 중이거나 일시정지된 회의방은 나간 후 삭제해 주세요.');
    }
    if (room.batchJobId != null && _isBatchProcessing(room.status)) {
      const message =
          '배치 처리 중인 회의는 삭제할 수 없습니다. '
          '현재 백엔드에 작업 취소 API가 없어 완료 또는 실패 후 삭제해야 합니다.';
      errorMessage = message;
      notifyListeners();
      throw const AppException(message);
    }

    _deletedLocalIds.add(room.localId);
    _batchPollTimers.remove(room.localId)?.cancel();
    _realtimeMinutesPollTimers.remove(room.localId)?.cancel();
    try {
      final backendId = room.backendId;
      if (backendId != null && backendId.isNotEmpty) {
        await _api.deleteTranscriptSegments(backendId);
        await _api.deleteMeetingArtifacts(backendId);
      }
      await _deleteLocalFile(room.recording?.filePath);
      await _deleteLocalFile(room.transcriptFilePath);
      await _repository.deleteRoom(room.localId);
      if (selectedRoom?.localId == room.localId) {
        selectedRoom = null;
      }
      rooms = await _repository.listRooms(query: query);
      statusMessage = '회의방의 서버 산출물과 기기 데이터를 삭제했습니다.';
      errorMessage = null;
      notifyListeners();
    } catch (error) {
      _deletedLocalIds.remove(room.localId);
      errorMessage = _userMessage(error);
      notifyListeners();
      rethrow;
    }
  }

  /// backend presigned URL로 PDF를 다운로드한 뒤 기기의 PDF 앱으로 엽니다.
  Future<void> downloadAndOpenPdf() async {
    final room = selectedRoom;
    if (room == null) return;
    final backendId = room.backendId;
    if (backendId == null || backendId.isEmpty || room.pdfS3Key == null) {
      errorMessage = '다운로드할 회의록 PDF가 아직 준비되지 않았습니다.';
      notifyListeners();
      return;
    }

    isDownloadingPdf = true;
    errorMessage = null;
    statusMessage = '회의록 PDF를 다운로드하고 있습니다.';
    notifyListeners();
    try {
      final payload = await _api.requestPdfDownloadUrl(backendId);
      final downloadUrl = payload['download_url'];
      if (downloadUrl is! String || downloadUrl.isEmpty) {
        throw const AppException('PDF 다운로드 URL이 없습니다.');
      }
      final bytes = await _api.downloadFileBytes(downloadUrl);
      await _pdfDownloadService.saveAndOpen(
        meetingId: room.meetingId,
        title: room.title,
        bytes: bytes,
      );
      statusMessage = '회의록 PDF를 저장하고 열었습니다.';
    } catch (error) {
      errorMessage = _userMessage(error);
    } finally {
      isDownloadingPdf = false;
      notifyListeners();
    }
  }

  /// backend presigned URL로 DOCX를 다운로드한 뒤 기기의 문서 앱으로 엽니다.
  Future<void> downloadAndOpenDocx() async {
    final room = selectedRoom;
    if (room == null) return;
    final backendId = room.backendId;
    if (backendId == null || backendId.isEmpty || room.docxS3Key == null) {
      errorMessage = '다운로드할 회의록 DOCX가 아직 준비되지 않았습니다.';
      notifyListeners();
      return;
    }

    isDownloadingDocx = true;
    errorMessage = null;
    statusMessage = '회의록 DOCX를 다운로드하고 있습니다.';
    notifyListeners();
    try {
      final payload = await _api.requestDocxDownloadUrl(backendId);
      final downloadUrl = payload['download_url'];
      if (downloadUrl is! String || downloadUrl.isEmpty) {
        throw const AppException('DOCX 다운로드 URL이 없습니다.');
      }
      final bytes = await _api.downloadFileBytes(downloadUrl);
      await _pdfDownloadService.saveDocxAndOpen(
        meetingId: room.meetingId,
        title: room.title,
        bytes: bytes,
      );
      statusMessage = '회의록 DOCX를 저장하고 열었습니다.';
    } catch (error) {
      errorMessage = _userMessage(error);
    } finally {
      isDownloadingDocx = false;
      notifyListeners();
    }
  }

  Future<void> downloadAndOpenTranscript({required bool batch}) async {
    final room = selectedRoom;
    if (room == null) return;
    final backendId = room.backendId;
    if (backendId == null || backendId.isEmpty) {
      errorMessage = '전사문을 조회할 백엔드 회의 ID가 없습니다.';
      notifyListeners();
      return;
    }

    isDownloadingTranscript = true;
    errorMessage = null;
    statusMessage = batch ? '배치 전사문을 다운로드하고 있습니다.' : '실시간 전사문을 다운로드하고 있습니다.';
    notifyListeners();
    try {
      final bytes = batch
          ? await _api.downloadBatchTranscript(backendId)
          : await _api.downloadRealtimeTranscript(backendId);
      final path = await _transcriptDownloadService.saveAndOpen(
        meetingId: room.meetingId,
        source: batch ? 'batch' : 'realtime',
        bytes: bytes,
      );
      final updated = batch
          ? room
          : room.copyWith(transcriptFilePath: path, updatedAt: DateTime.now());
      await _saveAndSelect(updated, '전사문을 저장하고 열었습니다.');
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
    } finally {
      isDownloadingTranscript = false;
      notifyListeners();
    }
  }

  /// 캘린더 등록 후보로 사용할 후속 조치 목록을 backend에서 다시 조회합니다.
  Future<void> refreshActionItems() async {
    final room = selectedRoom;
    if (room == null) return;
    final backendId = room.backendId;
    if (backendId == null || backendId.isEmpty) {
      errorMessage = '액션 플랜을 조회할 백엔드 회의 ID가 없습니다.';
      notifyListeners();
      return;
    }

    isRefreshingActionItems = true;
    errorMessage = null;
    statusMessage = '캘린더용 액션 플랜을 조회하고 있습니다.';
    notifyListeners();
    try {
      final payload = await _api.getMeetingActionItems(backendId);
      final updated = room.copyWith(
        actionItems: _actionItems(payload['action_items']),
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(updated, '캘린더용 액션 플랜을 업데이트했습니다.');
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
    } finally {
      isRefreshingActionItems = false;
      notifyListeners();
    }
  }

  Future<void> startBatchTranscription({
    required bool useSavedRecording,
  }) async {
    final room = selectedRoom;
    if (room == null || isStartingBatch) return;
    final targetLocalId = room.localId;
    if (_activeRecordingLocalId != null) {
      errorMessage = '진행 중인 실시간 녹음을 먼저 종료해 주세요.';
      notifyListeners();
      return;
    }
    if (room.batchJobId != null && _isBatchProcessing(room.status)) {
      errorMessage = '이미 배치 작업이 진행 중입니다.';
      notifyListeners();
      return;
    }

    isStartingBatch = true;
    errorMessage = null;
    notifyListeners();
    try {
      final pickedRecording = useSavedRecording
          ? room.recording
          : await _audioFilePickerService.pickAudioFile();
      if (pickedRecording == null) {
        if (useSavedRecording) {
          throw const AppException('이 회의방에 저장된 녹음 파일이 없습니다.');
        }
        statusMessage = '파일 선택을 취소했습니다.';
        return;
      }
      if (pickedRecording.filePath.contains('://')) {
        throw const AppException('실제 저장된 오디오 파일만 배치 업로드할 수 있습니다.');
      }

      final file = File(pickedRecording.filePath);
      if (!await file.exists()) {
        throw const AppException('선택한 녹음 파일을 찾을 수 없습니다.');
      }
      final extension = p
          .extension(pickedRecording.fileName)
          .replaceFirst('.', '')
          .toLowerCase();
      if (!_batchAudioExtensions.contains(extension)) {
        throw AppException('지원하지 않는 오디오 형식입니다: .$extension');
      }

      final backendMeetingId = await _ensureBackendMeeting(room);
      final uploadingRecording = pickedRecording.copyWith(
        fileSizeBytes: await file.length(),
      );
      final uploading = room.copyWith(
        backendId: backendMeetingId,
        recording: uploadingRecording,
        status: MeetingStatus.uploading,
        updatedAt: DateTime.now(),
        clearBatchStatus: true,
        clearBatchError: true,
      );
      await _saveAndSelect(uploading, '녹음 파일 업로드 URL을 요청하고 있습니다.');

      final uploadPayload = await _api.requestAudioUploadUrl(
        backendMeetingId,
        fileExtension: extension,
        contentType: uploadingRecording.contentType,
      );
      final uploadUrl = uploadPayload['upload_url'];
      final s3Key = uploadPayload['s3_key'];
      if (uploadUrl is! String || uploadUrl.isEmpty || s3Key is! String) {
        throw const AppException('백엔드 업로드 URL 응답이 올바르지 않습니다.');
      }

      await _api.uploadAudioFile(
        uploadUrl,
        filePath: uploadingRecording.filePath,
        contentType: uploadingRecording.contentType,
      );
      final confirmPayload = await _api.confirmAudioUpload(backendMeetingId);
      if (confirmPayload['uploaded'] != true ||
          confirmPayload['status'] != MeetingStatus.uploaded.value) {
        throw const AppException('백엔드에서 녹음 파일 업로드를 확인하지 못했습니다.');
      }
      final confirmedS3Key = confirmPayload['audio_s3_key'];
      if (confirmedS3Key is! String || confirmedS3Key.isEmpty) {
        throw const AppException('업로드 확인 응답에 S3 키가 없습니다.');
      }
      final uploaded = uploading.copyWith(
        recording: uploadingRecording.copyWith(audioS3Key: confirmedS3Key),
        status: MeetingStatus.uploaded,
        batchStatus: BatchTranscriptionStatus.uploaded,
        uploadedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(uploaded, '녹음 파일 업로드가 완료되었습니다.');

      final startPayload = await _api.startMeetingPipeline(backendMeetingId);
      final jobId = startPayload['job_id'];
      if (jobId is! String || jobId.isEmpty) {
        throw const AppException('배치 작업 ID를 받지 못했습니다.');
      }
      final queued = uploaded.copyWith(
        status: MeetingStatus.fromJson(
          startPayload['status'] as String?,
          fallback: MeetingStatus.queued,
        ),
        batchJobId: jobId,
        batchStatus: BatchTranscriptionStatus.queued,
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(queued, '배치 전사 및 회의록 생성 작업이 대기 중입니다.');
      _scheduleBatchPoll(queued.localId, immediate: true);
    } catch (error) {
      final current = await _repository.getRoom(targetLocalId) ?? room;
      final failed = current.copyWith(
        status: MeetingStatus.failed,
        batchStatus: BatchTranscriptionStatus.failed,
        batchErrorMessage: _userMessage(error),
        updatedAt: DateTime.now(),
      );
      await _saveKeepingSelection(failed, '배치 작업을 시작하지 못했습니다.');
      errorMessage = _userMessage(error);
    } finally {
      isStartingBatch = false;
      notifyListeners();
    }
  }

  Future<void> refreshBatchStatus() async {
    final room = selectedRoom;
    if (room == null || room.batchJobId == null) {
      errorMessage = '조회할 배치 작업이 없습니다.';
      notifyListeners();
      return;
    }
    _batchPollTimers.remove(room.localId)?.cancel();
    await _pollBatchJob(room.localId);
  }

  void _scheduleBatchPoll(String localId, {bool immediate = false}) {
    _batchPollTimers.remove(localId)?.cancel();
    if (immediate) {
      unawaited(_pollBatchJob(localId));
      return;
    }
    _batchPollTimers[localId] = Timer(
      _batchPollInterval,
      () => unawaited(_pollBatchJob(localId)),
    );
  }

  Future<void> _pollBatchJob(String localId) async {
    if (!_batchPollingLocalIds.add(localId)) return;
    try {
      final room = await _repository.getRoom(localId);
      final jobId = room?.batchJobId;
      final backendId = room?.backendId;
      if (room == null || jobId == null || backendId == null) return;

      final batchStatusPayload = await _api.getBatchStatus(backendId);
      final meeting = await _api.getMeeting(backendId);
      final batchStatus = BatchTranscriptionStatus.fromCode(
        batchStatusPayload['batch_status_code'],
      );
      final meetingStatus =
          batchStatus?.meetingStatus ??
          MeetingStatus.fromJson(
            batchStatusPayload['status'] as String? ??
                meeting['status'] as String?,
            fallback: room.status,
          );
      final polledRecording = room.recording?.copyWith(
        audioS3Key: meeting['audio_s3_key'] as String?,
        transcriptS3Key: meeting['transcript_s3_key'] as String?,
      );
      if (meetingStatus == MeetingStatus.failed) {
        _batchPollTimers.remove(localId)?.cancel();
        final job = await _api.getJob(jobId);
        final message =
            job['error_message'] as String? ??
            meeting['error_message'] as String? ??
            '배치 작업에 실패했습니다.';
        await _saveKeepingSelection(
          room.copyWith(
            status: MeetingStatus.failed,
            batchStatus: batchStatus ?? BatchTranscriptionStatus.failed,
            recording: polledRecording,
            batchErrorMessage: message,
            updatedAt: DateTime.now(),
          ),
          message,
        );
        return;
      }

      if (meetingStatus == MeetingStatus.completed) {
        _batchPollTimers.remove(localId)?.cancel();
        final result = await _api.getMeetingResult(backendId);
        final actionItems = await _actionItemsFromBackendOrResult(
          backendId,
          result,
        );
        await _saveKeepingSelection(
          room.copyWith(
            status: MeetingStatus.completed,
            batchStatus: batchStatus ?? BatchTranscriptionStatus.completed,
            recording: polledRecording,
            summary: result['summary'] as String?,
            decisions: _stringList(result['decisions']),
            openIssues: _stringList(result['open_issues']),
            actionItems: actionItems,
            minutesJsonS3Key: result['minutes_json_s3_key'] as String?,
            minutesMarkdownS3Key: result['minutes_markdown_s3_key'] as String?,
            pdfS3Key: result['pdf_s3_key'] as String?,
            docxS3Key: result['docx_s3_key'] as String?,
            updatedAt: DateTime.now(),
            clearBatchError: true,
          ),
          '배치 전사와 회의록 생성이 완료되었습니다.',
        );
        return;
      }

      await _saveKeepingSelection(
        room.copyWith(
          status: meetingStatus,
          batchStatus: batchStatus,
          recording: polledRecording,
          updatedAt: DateTime.now(),
        ),
        _messageFor(meetingStatus),
      );
      _scheduleBatchPoll(localId);
    } catch (error) {
      final room = await _repository.getRoom(localId);
      if (room != null) {
        await _saveKeepingSelection(
          room.copyWith(
            batchErrorMessage: _userMessage(error),
            updatedAt: DateTime.now(),
          ),
          '상태 조회에 실패했습니다. 잠시 후 다시 시도합니다.',
        );
        _scheduleBatchPoll(localId);
      }
    } finally {
      _batchPollingLocalIds.remove(localId);
    }
  }

  /// 마이크 권한을 확인한 뒤 backend WebSocket에 PCM 스트림을 전송합니다.
  Future<void> startRecording() async {
    final room = selectedRoom;
    if (room == null) return;

    if (room.batchJobId != null && _isBatchProcessing(room.status)) {
      errorMessage = '배치 처리 중인 회의방에서는 실시간 녹음을 시작할 수 없습니다.';
      notifyListeners();
      return;
    }
    if (isRecordingAnotherRoom(room.localId)) {
      errorMessage =
          '${activeRecordingRoomTitle ?? '다른 회의방'}에서 녹음이 진행 중입니다. '
          '해당 회의방의 녹음을 먼저 종료해 주세요.';
      notifyListeners();
      return;
    }

    final granted = await _permissionService.ensureGranted();
    if (!granted) {
      errorMessage = '마이크 권한이 필요합니다.';
      notifyListeners();
      return;
    }

    final isNewSession = _activeRecordingLocalId == null;
    _activeRecordingLocalId = room.localId;
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
      debugPrint('Realtime recording start failed: $error');
      await _stopRealtimeStream(controlType: 'stop');
      if (isNewSession) {
        _activeRecordingLocalId = null;
      }
      final failed = (selectedRoom ?? room).copyWith(
        status: MeetingStatus.paused,
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(failed, '실시간 스트림 연결에 실패했습니다.');
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
      savedRecordingWarning ?? 'PCM 오디오를 FastAPI로 전송 중입니다.',
    );
  }

  /// 현재 WebSocket/오디오 스트림을 닫고 transcript 누적 상태는 보존합니다.
  Future<void> pauseRecording() async {
    final room = selectedRoom;
    if (room == null) return;
    if (_activeRecordingLocalId != room.localId) {
      errorMessage = '현재 회의방에서 진행 중인 녹음이 없습니다.';
      notifyListeners();
      return;
    }

    await _stopRealtimeStream(controlType: 'pause');
    await _pauseSavedRecording();

    final updated = room.copyWith(
      status: MeetingStatus.paused,
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(updated, '일시정지되었습니다. 녹음을 다시 누르면 새 스트림으로 이어집니다.');
  }

  /// 회의방을 나가며 realtime stream을 종료하고 transcript 파일을 로컬에 저장합니다.
  Future<void> leaveRoom() async {
    final room = selectedRoom;
    if (room == null) return;
    if (_activeRecordingLocalId != null &&
        _activeRecordingLocalId != room.localId) {
      errorMessage = '${activeRecordingRoomTitle ?? '다른 회의방'}에서 녹음이 진행 중입니다.';
      notifyListeners();
      return;
    }

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
    await _saveAndSelect(updated, '녹음 파일과 대화록이 로컬에 저장되었습니다.');
    _activeRecordingLocalId = null;
    notifyListeners();
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
      speaker: '화자 1',
    );

    final updated = room.copyWith(
      status: room.status == MeetingStatus.paused
          ? MeetingStatus.paused
          : MeetingStatus.recording,
      segments: [...room.segments, segment],
      updatedAt: DateTime.now(),
      clearPartialTranscript: true,
    );
    await _saveAndSelect(updated, '최종 대화록을 받았습니다.');
  }

  /// 최종 transcript segment를 backend에 보내고 진행률을 polling하며 회의록을 생성합니다.
  Future<void> generateMinutesFromRealtime() async {
    final room = selectedRoom;
    if (room == null) return;
    if (room.batchJobId != null && _isBatchProcessing(room.status)) {
      errorMessage = '배치 전사와 회의록 생성이 진행 중입니다. 완료 후 결과를 확인해 주세요.';
      notifyListeners();
      return;
    }
    if (_isRealtimeMinutesProcessing(room)) {
      _scheduleRealtimeMinutesPoll(room.localId, immediate: true);
      errorMessage = '이미 실시간 회의록 생성이 진행 중입니다.';
      notifyListeners();
      return;
    }

    try {
      final backendMeetingId = await _ensureBackendMeeting(room);
      final initialProgress = const RealtimeMinutesProgress(
        statusCode: 5,
        percent: 0,
        step: 'requested',
        message: '회의록 생성을 요청했습니다.',
      );
      final generating = room.copyWith(
        backendId: backendMeetingId,
        status: MeetingStatus.summarizing,
        realtimeMinutesProgress: initialProgress,
        updatedAt: DateTime.now(),
      );
      await _saveAndSelect(generating, '실시간 대화록 기반 회의록 생성을 요청 중입니다.');
      errorMessage = null;
      notifyListeners();
      final segments = generating.segments.isEmpty
          ? null
          : generating.segments
                .map(
                  (segment) => {
                    'speaker_label': segment.speaker,
                    'start_time_ms': segment.startedAt.inMilliseconds,
                    'end_time_ms': segment.endedAt.inMilliseconds,
                    'confidence_score': segment.confidenceScore,
                    'is_low_confidence': segment.isLowConfidence,
                    'transcript_text': segment.text,
                  },
                )
                .toList(growable: false);
      final startPayload = await _api.startMinutesFromRealtime(
        backendMeetingId,
        segments: segments,
      );
      final startedProgress =
          RealtimeMinutesProgress.fromJson(startPayload) ?? initialProgress;
      await _saveAndSelect(
        generating.copyWith(
          status: MeetingStatus.fromJson(
            startPayload['status'] as String?,
            fallback: MeetingStatus.summarizing,
          ),
          realtimeMinutesProgress: startedProgress,
          updatedAt: DateTime.now(),
        ),
        startedProgress.message ?? '실시간 회의록 생성이 시작되었습니다.',
      );
      _scheduleRealtimeMinutesPoll(generating.localId, immediate: true);
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
    }
  }

  void _scheduleRealtimeMinutesPoll(String localId, {bool immediate = false}) {
    _realtimeMinutesPollTimers.remove(localId)?.cancel();
    if (immediate) {
      unawaited(_pollRealtimeMinutes(localId));
      return;
    }
    _realtimeMinutesPollTimers[localId] = Timer(
      _realtimeMinutesPollInterval,
      () => unawaited(_pollRealtimeMinutes(localId)),
    );
  }

  Future<void> _pollRealtimeMinutes(String localId) async {
    if (!_realtimeMinutesPollingLocalIds.add(localId)) return;
    try {
      final room = await _repository.getRoom(localId);
      final backendId = room?.backendId;
      if (room == null || backendId == null) return;

      final payload = await _api.getRealtimeProgress(backendId);
      final progress = RealtimeMinutesProgress.fromJson(payload);
      final status = MeetingStatus.fromJson(
        payload['status'] as String?,
        fallback: room.status,
      );

      if (progress?.failed == true) {
        _realtimeMinutesPollTimers.remove(localId)?.cancel();
        await _saveKeepingSelection(
          room.copyWith(
            status: MeetingStatus.failed,
            realtimeMinutesProgress: progress,
            updatedAt: DateTime.now(),
          ),
          progress?.message ?? '실시간 회의록 생성에 실패했습니다.',
        );
        return;
      }

      if (progress?.completed == true || (progress?.percent ?? 0) >= 100) {
        _realtimeMinutesPollTimers.remove(localId)?.cancel();
        final result = await _api.getMeetingResult(backendId);
        final actionItems = await _actionItemsFromBackendOrResult(
          backendId,
          result,
        );
        await _saveKeepingSelection(
          room.copyWith(
            status: _statusAfterRealtimeMinutes(result),
            title: result['title'] as String?,
            summary: result['summary'] as String?,
            decisions: _stringList(result['decisions']),
            openIssues: _stringList(result['open_issues']),
            actionItems: actionItems,
            minutesJsonS3Key: result['minutes_json_s3_key'] as String?,
            minutesMarkdownS3Key: result['minutes_markdown_s3_key'] as String?,
            pdfS3Key: result['pdf_s3_key'] as String?,
            docxS3Key: result['docx_s3_key'] as String?,
            realtimeMinutesProgress:
                progress ??
                const RealtimeMinutesProgress(
                  statusCode: 6,
                  percent: 100,
                  step: 'completed',
                  message: '회의록 생성이 완료되었습니다.',
                  completed: true,
                ),
            uploadedAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          '실시간 회의록 생성이 완료되었습니다.',
        );
        return;
      }

      await _saveKeepingSelection(
        room.copyWith(
          status: status,
          realtimeMinutesProgress: progress,
          updatedAt: DateTime.now(),
        ),
        progress?.message ?? _messageFor(status),
      );
      _scheduleRealtimeMinutesPoll(localId);
    } catch (error) {
      final room = await _repository.getRoom(localId);
      if (room != null) {
        await _saveKeepingSelection(
          room.copyWith(updatedAt: DateTime.now()),
          '실시간 회의록 진행률 조회에 실패했습니다. 잠시 후 다시 시도합니다.',
        );
        _scheduleRealtimeMinutesPoll(localId);
      }
    } finally {
      _realtimeMinutesPollingLocalIds.remove(localId);
    }
  }

  Future<bool> addActionItemToCalendar({
    required int actionItemIndex,
    required DateTime date,
    required String title,
  }) async {
    final room = selectedRoom;
    if (room == null) return false;
    if (actionItemIndex < 0 || actionItemIndex >= room.actionItems.length) {
      errorMessage = '추가할 액션 아이템을 찾을 수 없습니다.';
      notifyListeners();
      return false;
    }

    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      errorMessage = '일정 내용을 입력해 주세요.';
      notifyListeners();
      return false;
    }

    final startAt = DateTime(date.year, date.month, date.day);
    final endAt = startAt.add(const Duration(days: 1));
    final item = room.actionItems[actionItemIndex];
    isAddingCalendarEvent = true;
    errorMessage = null;
    statusMessage = '캘린더에 일정을 추가하고 있습니다.';
    notifyListeners();
    try {
      final eventId = await _calendarEventService.addEvent(
        title: trimmedTitle,
        startAt: startAt,
        endAt: endAt,
        allDay: true,
        notes:
            'VoiceDoc 회의: ${room.title}\n'
            '회의 ID: ${room.meetingId}\n'
            '담당자: ${item.displayOwner}',
      );
      final items = [...room.actionItems];
      items[actionItemIndex] = item.copyWith(
        task: trimmedTitle,
        dueDateResolved: _dateOnly(startAt),
        calendarEventId: eventId,
        calendarAddedAt: DateTime.now(),
      );
      await _saveAndSelect(
        room.copyWith(actionItems: items, updatedAt: DateTime.now()),
        '캘린더에 일정을 추가했습니다.',
      );
      return true;
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
      return false;
    } finally {
      isAddingCalendarEvent = false;
      notifyListeners();
    }
  }

  Future<void> openCalendar({DateTime? date}) async {
    try {
      await _calendarEventService.openCalendar(date: date);
    } catch (error) {
      errorMessage = _userMessage(error);
      notifyListeners();
    }
  }

  /// 기존 UI 콜백과의 호환을 위한 별칭입니다. 실제 동작은 회의록 생성입니다.
  Future<void> requestUpload() => generateMinutesFromRealtime();

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
        throw const AppException('백엔드 응답에 meeting id가 없습니다.');
      }

      final updated = room.copyWith(
        backendId: backendId,
        updatedAt: DateTime.now(),
      );
      if (_deletedLocalIds.contains(room.localId)) {
        return backendId;
      }
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

  /// 목업 테스트 UI와 맞추기 위해 회의록 S3 산출물이 있으면 로컬 상태를 uploaded로 봅니다.
  MeetingStatus _statusAfterRealtimeMinutes(Map<String, dynamic> result) {
    final hasMinutesArtifact =
        result['minutes_json_s3_key'] != null ||
        result['minutes_markdown_s3_key'] != null ||
        result['pdf_s3_key'] != null ||
        result['docx_s3_key'] != null;
    if (hasMinutesArtifact) return MeetingStatus.uploaded;
    return MeetingStatus.fromJson(result['status'] as String?);
  }

  /// WebSocket 이벤트 스트림을 controller 상태 변경으로 변환합니다.
  void _listenToTranscriptionEvents() {
    unawaited(_transcriptionSubscription?.cancel());
    _transcriptionSubscription = _transcriptionSocketClient.events.listen((
      event,
    ) {
      _transcriptionEventQueue = _transcriptionEventQueue.then(
        (_) => _handleTranscriptionEvent(event),
      );
    });
  }

  /// backend에서 받은 status/partial/final/error 이벤트를 UI 모델에 반영합니다.
  Future<void> _handleTranscriptionEvent(TranscriptionEvent event) async {
    final activeLocalId = _activeRecordingLocalId;
    if (activeLocalId == null) return;
    final room = await _repository.getRoom(activeLocalId);
    if (room == null) return;
    final isActiveRoomSelected = selectedRoom?.localId == activeLocalId;

    switch (event) {
      case TranscriptionStatusEvent():
        final progress = event.realtimeStatusCode == null
            ? room.realtimeMinutesProgress
            : RealtimeMinutesProgress(
                statusCode: event.realtimeStatusCode,
                percent: room.realtimeMinutesProgress?.percent,
                step: room.realtimeMinutesProgress?.step,
                message: room.realtimeMinutesProgress?.message,
                updatedAt: room.realtimeMinutesProgress?.updatedAt,
                completed: room.realtimeMinutesProgress?.completed ?? false,
                failed: room.realtimeMinutesProgress?.failed ?? false,
              );
        if (progress != room.realtimeMinutesProgress) {
          await _saveKeepingSelection(
            room.copyWith(
              realtimeMinutesProgress: progress,
              updatedAt: DateTime.now(),
            ),
          );
        }
        if (isActiveRoomSelected) {
          statusMessage = event.message;
          notifyListeners();
        }
      case PartialTranscriptEvent():
        final updated = room.copyWith(
          partialTranscript: event.text,
          updatedAt: DateTime.now(),
        );
        await _saveKeepingSelection(updated);
      case FinalTranscriptEvent():
        final segment = _withElapsedFallback(event.segment);
        final updated = room.copyWith(
          segments: [...room.segments, segment],
          updatedAt: DateTime.now(),
          clearPartialTranscript: true,
        );
        await _saveKeepingSelection(updated, '최종 대화록을 받았습니다.');
      case TranscriptionErrorEvent():
        if (isActiveRoomSelected) {
          errorMessage = event.message;
          notifyListeners();
        }
    }
  }

  Future<void> _saveKeepingSelection(
    MeetingRoom room, [
    String? activeRoomMessage,
  ]) async {
    final selectedLocalId = selectedRoom?.localId;
    final saved = await _repository.saveRoom(room);
    rooms = await _repository.listRooms(query: query);
    if (selectedLocalId == room.localId) {
      selectedRoom = saved;
      if (activeRoomMessage != null) {
        statusMessage = activeRoomMessage;
      }
    }
    notifyListeners();
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
      speaker: segment.speaker,
      confidenceScore: segment.confidenceScore,
      isLowConfidence: segment.isLowConfidence,
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
      return 'PCM 스트리밍은 진행 중이지만 녹음 파일 저장을 시작하지 못했습니다: $error';
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

  bool _isActive(MeetingStatus status) {
    return status == MeetingStatus.recording ||
        status == MeetingStatus.paused ||
        status == MeetingStatus.transcribing;
  }

  bool _isBatchProcessing(MeetingStatus status) {
    return status == MeetingStatus.uploading ||
        status == MeetingStatus.uploaded ||
        status == MeetingStatus.queued ||
        status == MeetingStatus.transcribing ||
        status == MeetingStatus.summarizing;
  }

  bool _isRealtimeMinutesProcessing(MeetingRoom room) {
    return room.realtimeMinutesProgress?.isProcessing == true ||
        room.status == MeetingStatus.summarizing;
  }

  Future<void> _deleteLocalFile(String? path) async {
    if (path == null || path.isEmpty || path.contains('://')) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
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
      MeetingStatus.ready => '준비되었습니다. 녹음을 누르면 PCM 오디오 스트리밍을 시작합니다.',
      MeetingStatus.created => '회의방이 생성되었습니다.',
      MeetingStatus.uploadUrlIssued => '업로드 URL이 발급되었습니다.',
      MeetingStatus.uploading => '회의록 생성을 준비 중입니다.',
      MeetingStatus.uploaded => 'S3 업로드가 완료되었습니다.',
      MeetingStatus.queued => '작업이 대기 중입니다.',
      MeetingStatus.orchestrationStarting => '워크플로를 시작 중입니다.',
      MeetingStatus.orchestrationStarted => '워크플로가 시작되었습니다.',
      MeetingStatus.recording => '백엔드 상태: 변환 중',
      MeetingStatus.paused => '실시간 변환이 일시정지되었습니다.',
      MeetingStatus.transcribing => '백엔드 상태: 변환 중',
      MeetingStatus.transcriptionCompleted => '대화록 변환이 완료되었습니다.',
      MeetingStatus.summaryQueued => '요약 작업이 대기 중입니다.',
      MeetingStatus.summarizing => '대화록을 요약 중입니다.',
      MeetingStatus.generatingMinutes => '회의록을 생성 중입니다.',
      MeetingStatus.completed => '회의록이 준비되었습니다.',
      MeetingStatus.failed => '처리에 실패했습니다.',
    };
  }

  /// 개발자용 예외를 사용자에게 보여줄 한국어 메시지로 변환합니다.
  String _userMessage(Object error) {
    if (error is AppException) return error.message;
    return '요청에 실패했습니다. 서버와 네트워크 상태를 확인해 주세요.';
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  List<ActionItem> _actionItems(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => ActionItem.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.task.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<ActionItem>> _actionItemsFromBackendOrResult(
    String backendMeetingId,
    Map<String, dynamic> result,
  ) async {
    try {
      final payload = await _api.getMeetingActionItems(backendMeetingId);
      return _actionItems(payload['action_items']);
    } catch (error) {
      return _actionItems(result['action_items']);
    }
  }

  String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    for (final timer in _batchPollTimers.values) {
      timer.cancel();
    }
    for (final timer in _realtimeMinutesPollTimers.values) {
      timer.cancel();
    }
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
  '실시간 변환 테스트 이벤트입니다.',
];

const _batchAudioExtensions = {
  'm4a',
  'mp3',
  'mp4',
  'wav',
  'flac',
  'ogg',
  'amr',
  'webm',
};
