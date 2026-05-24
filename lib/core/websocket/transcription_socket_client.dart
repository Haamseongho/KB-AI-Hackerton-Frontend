import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/meetings/domain/transcript_segment.dart';
import '../../features/meetings/domain/transcription_event.dart';
import '../config/app_config.dart';

class TranscriptionSocketClient {
  TranscriptionSocketClient({String? wsBaseUrl})
    : _wsBaseUrl = wsBaseUrl ?? AppConfig.wsBaseUrl;

  final String _wsBaseUrl;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _events = StreamController<TranscriptionEvent>.broadcast();

  Stream<TranscriptionEvent> get events => _events.stream;

  Future<void> connect({
    required String meetingId,
    int sampleRate = 16000,
    int channels = 1,
    int chunkDurationMs = 100,
    String encoding = 'pcm_s16le',
    String languageCode = 'ko-KR',
  }) async {
    await close();
    final uri = Uri.parse('$_wsBaseUrl/ws/meetings/$meetingId/transcribe');
    _channel = WebSocketChannel.connect(uri);
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: (Object error) {
        _events.add(TranscriptionErrorEvent(message: error.toString()));
      },
      onDone: () {
        _events.add(
          const TranscriptionStatusEvent(
            status: 'closed',
            message: 'WebSocket closed',
          ),
        );
      },
    );
    _sendJson({
      'type': 'start',
      'meeting_id': meetingId,
      'sample_rate': sampleRate,
      'encoding': encoding,
      'channels': channels,
      'chunk_duration_ms': chunkDurationMs,
      'language_code': languageCode,
    });
  }

  void sendPcmChunk(Uint8List bytes) {
    _channel?.sink.add(bytes);
  }

  void pause() {
    _sendJson({'type': 'pause'});
  }

  void resume() {
    _sendJson({'type': 'resume'});
  }

  Future<void> stop() async {
    _sendJson({'type': 'stop'});
    await close();
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    unawaited(close());
    unawaited(_events.close());
  }

  void _sendJson(Map<String, dynamic> json) {
    _channel?.sink.add(jsonEncode(json));
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;

    final decoded = jsonDecode(message);
    if (decoded is! Map<String, dynamic>) return;

    final type = decoded['type'] as String?;
    switch (type) {
      case 'transcription_status':
        _events.add(
          TranscriptionStatusEvent(
            status: decoded['status'] as String? ?? 'unknown',
            message: decoded['message'] as String? ?? 'Status updated',
          ),
        );
      case 'partial_transcript':
        _events.add(
          PartialTranscriptEvent(text: decoded['text'] as String? ?? ''),
        );
      case 'final_transcript':
        _events.add(
          FinalTranscriptEvent(
            segment: TranscriptSegment(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              text: decoded['text'] as String? ?? '',
              speaker: decoded['speaker'] as String?,
              startedAt: Duration(
                milliseconds: decoded['started_at_ms'] as int? ?? 0,
              ),
              endedAt: Duration(
                milliseconds: decoded['ended_at_ms'] as int? ?? 0,
              ),
              isFinal: true,
            ),
          ),
        );
      case 'error':
        _events.add(
          TranscriptionErrorEvent(
            message: decoded['message'] as String? ?? 'Transcription failed',
          ),
        );
    }
  }
}
