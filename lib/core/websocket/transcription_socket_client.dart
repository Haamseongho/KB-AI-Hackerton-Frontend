import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/meetings/domain/transcript_segment.dart';
import '../../features/meetings/domain/transcription_event.dart';
import '../config/app_config.dart';
import '../errors/app_exception.dart';

/// FastAPI realtime STT WebSocket과 통신하는 클라이언트입니다.
///
/// UI나 controller가 raw JSON을 직접 다루지 않도록 backend 이벤트를
/// `TranscriptionEvent` 타입으로 변환해서 외부에 전달합니다.
class TranscriptionSocketClient {
  TranscriptionSocketClient({String? wsBaseUrl})
    : _wsBaseUrl = wsBaseUrl ?? AppConfig.wsBaseUrl;

  final String _wsBaseUrl;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _events = StreamController<TranscriptionEvent>.broadcast();

  /// status, partial transcript, final transcript, error 이벤트를 발행합니다.
  Stream<TranscriptionEvent> get events => _events.stream;

  /// backend UUID 기준 meeting WebSocket에 연결하고 start 이벤트를 보냅니다.
  Future<void> connect({
    required String meetingId,
    int sampleRate = 16000,
    int channels = 1,
    int chunkDurationMs = 100,
    String mediaEncoding = 'pcm',
    String languageCode = 'ko-KR',
    String? vocabularyName,
  }) async {
    await close();
    final uri = Uri.parse('$_wsBaseUrl/ws/meetings/$meetingId/transcribe');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      await close();
      throw AppException('실시간 전사 서버 연결 시간이 초과되었습니다: $uri');
    } catch (error) {
      await close();
      throw AppException('실시간 전사 WebSocket 연결에 실패했습니다: $error');
    }

    _subscription = channel.stream.listen(
      _handleMessage,
      onError: (Object error) {
        _events.add(TranscriptionErrorEvent(message: error.toString()));
      },
      onDone: () {
        _events.add(
          const TranscriptionStatusEvent(
            status: 'closed',
            message: 'WebSocket 연결이 종료되었습니다.',
          ),
        );
      },
    );
    _sendJson({
      'type': 'start',
      'meeting_id': meetingId,
      'sample_rate': sampleRate,
      'media_encoding': mediaEncoding,
      'language_code': languageCode,
      'vocabulary_name': ?vocabularyName,
    });
  }

  /// 녹음 서비스에서 받은 PCM 16-bit little-endian chunk를 순서대로 전송합니다.
  void sendPcmChunk(Uint8List bytes) {
    _channel?.sink.add(bytes);
  }

  /// backend에 pause 제어 이벤트를 보냅니다.
  void pause() {
    _sendJson({'type': 'pause'});
  }

  /// backend에 resume 제어 이벤트를 보냅니다.
  void resume() {
    _sendJson({'type': 'resume'});
  }

  /// backend에 stop 이벤트를 보낸 뒤 WebSocket을 닫습니다.
  Future<void> stop() async {
    _sendJson({'type': 'stop'});
    await close();
  }

  /// WebSocket 구독과 sink를 정리합니다.
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// 앱 종료나 controller dispose 시 내부 리소스를 해제합니다.
  void dispose() {
    unawaited(close());
    unawaited(_events.close());
  }

  /// Dart map을 JSON 문자열로 변환해 WebSocket에 전송합니다.
  void _sendJson(Map<String, dynamic> json) {
    _channel?.sink.add(jsonEncode(json));
  }

  /// backend JSON 이벤트를 앱 내부 typed event로 변환합니다.
  void _handleMessage(dynamic message) {
    if (message is! String) return;

    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) return;

    final type = decoded['type'] as String?;
    switch (type) {
      case 'status':
        _events.add(
          TranscriptionStatusEvent(
            status: decoded['status'] as String? ?? 'unknown',
            realtimeStatusCode: _intValue(decoded['realtime_status_code']),
            message:
                decoded['message'] as String? ??
                '백엔드 상태: ${decoded['status'] ?? 'unknown'}',
          ),
        );
      case 'transcript.partial':
        _events.add(
          PartialTranscriptEvent(
            text: decoded['transcript_text'] as String? ?? '',
          ),
        );
      case 'transcript.final':
        _events.add(
          FinalTranscriptEvent(
            segment: TranscriptSegment(
              id:
                  (decoded['segment_seq'] as int?)?.toString() ??
                  DateTime.now().microsecondsSinceEpoch.toString(),
              text: decoded['transcript_text'] as String? ?? '',
              speaker: decoded['speaker_label'] as String?,
              startedAt: Duration(
                milliseconds:
                    _intValue(decoded['start_time_ms']) ??
                    _intValue(decoded['started_at_ms']) ??
                    0,
              ),
              endedAt: Duration(
                milliseconds:
                    _intValue(decoded['end_time_ms']) ??
                    _intValue(decoded['ended_at_ms']) ??
                    0,
              ),
              isFinal: true,
              confidenceScore: _doubleValue(decoded['confidence_score']),
              isLowConfidence: decoded['is_low_confidence'] == true,
            ),
          ),
        );
      case 'error':
        _events.add(
          TranscriptionErrorEvent(
            message: decoded['message'] as String? ?? '실시간 변환에 실패했습니다.',
          ),
        );
    }
  }

  /// backend JSON 숫자가 int/double 어느 쪽으로 와도 millisecond 값으로 변환합니다.
  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// confidence score를 0~1 범위의 double로 안전하게 변환합니다.
  double? _doubleValue(Object? value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value);
    return null;
  }
}
