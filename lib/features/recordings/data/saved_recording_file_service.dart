import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../meetings/domain/recording_asset.dart';

/// 재생과 S3 업로드에 사용할 encoded 녹음 파일을 관리하는 서비스입니다.
///
/// 실시간 STT용 PCM 스트림과 별도의 `AudioRecorder`를 사용합니다. 일부 기기는
/// 마이크 동시 캡처를 제한할 수 있으므로, controller는 이 서비스 실패를 STT 실패로
/// 취급하지 않고 사용자에게 경고만 표시합니다.
class SavedRecordingFileService {
  SavedRecordingFileService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  String? _meetingId;
  DateTime? _activeStartedAt;
  Duration _recordedDuration = Duration.zero;

  /// 현재 회의의 m4a 녹음 파일 저장을 시작하거나 일시정지 상태에서 재개합니다.
  Future<void> startOrResume({
    required String meetingId,
    required String title,
  }) async {
    if (await _recorder.isRecording()) return;

    if (_path != null &&
        _meetingId == meetingId &&
        await _recorder.isPaused()) {
      await _recorder.resume();
      _activeStartedAt = DateTime.now();
      return;
    }

    final supported = await _recorder.isEncoderSupported(AudioEncoder.aacLc);
    if (!supported) {
      throw StateError('현재 기기에서 m4a 녹음 저장을 지원하지 않습니다.');
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'recordings'));
    await directory.create(recursive: true);

    _meetingId = meetingId;
    _recordedDuration = Duration.zero;
    _activeStartedAt = DateTime.now();
    _path = p.join(
      directory.path,
      '${_safeFileName(meetingId)}_${_safeFileName(title)}.m4a',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: _path!,
    );
  }

  /// 저장용 녹음 파일만 일시정지합니다. transcript와 realtime stream은 별도로 관리합니다.
  Future<void> pause() async {
    if (!await _recorder.isRecording()) return;
    _accumulateDuration();
    await _recorder.pause();
  }

  /// 저장용 녹음 파일을 종료하고 앱에서 보관할 recording metadata를 반환합니다.
  Future<RecordingAsset?> stop({
    required String meetingId,
    required String title,
  }) async {
    final hasSession = _path != null && _meetingId == meetingId;
    if (!hasSession) return null;

    if (await _recorder.isRecording()) {
      _accumulateDuration();
    }

    final stoppedPath = await _recorder.stop();
    final filePath = stoppedPath ?? _path;
    if (filePath == null) return null;

    final fileName = p.basename(filePath);
    final durationMs = _recordedDuration.inMilliseconds;
    _path = null;
    _meetingId = null;
    _activeStartedAt = null;
    _recordedDuration = Duration.zero;

    return RecordingAsset(
      fileName: fileName,
      filePath: filePath,
      contentType: 'audio/mp4',
      durationMs: durationMs,
      realtimeAudioEncoding: 'pcm',
      realtimeSampleRate: 16000,
      realtimeChannels: 1,
    );
  }

  /// recorder native resource를 해제합니다.
  Future<void> dispose() async {
    await _recorder.dispose();
  }

  void _accumulateDuration() {
    final startedAt = _activeStartedAt;
    if (startedAt == null) return;
    _recordedDuration += DateTime.now().difference(startedAt);
    _activeStartedAt = null;
  }

  String _safeFileName(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return safe.isEmpty ? 'meeting' : safe;
  }
}
