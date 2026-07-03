import 'dart:typed_data';

import 'package:record/record.dart';

import '../../../core/errors/app_exception.dart';

/// 마이크 입력을 Amazon Transcribe Streaming이 받을 수 있는 PCM 스트림으로 엽니다.
///
/// 저장용 녹음 파일 생성과 realtime STT용 PCM 전송은 요구사항이 다르므로,
/// 이 서비스는 WebSocket으로 보낼 raw PCM chunk 생성에만 집중합니다.
class RealtimeAudioStreamingService {
  RealtimeAudioStreamingService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// 16 kHz mono PCM 16-bit 스트림을 시작합니다.
  Future<Stream<Uint8List>> startPcmStream({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    try {
      final supported = await _recorder.isEncoderSupported(
        AudioEncoder.pcm16bits,
      );
      if (!supported) {
        throw const AppException('현재 기기에서 실시간 PCM 녹음 스트림을 지원하지 않습니다.');
      }

      return await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: channels,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
          streamBufferSize: 4096,
          androidConfig: const AndroidRecordConfig(
            // record 6.x의 foreground service로 백그라운드 마이크 캡처를 유지합니다.
            // ignore: deprecated_member_use
            service: AndroidService(
              title: 'VoiceDoc 회의 녹음 중',
              content: '실시간 대화록을 생성하고 있습니다.',
            ),
          ),
        ),
      );
    } on AppException {
      rethrow;
    } catch (error) {
      throw AppException('마이크 PCM 스트림을 시작하지 못했습니다: $error');
    }
  }

  /// 현재 실행 중인 PCM 녹음 스트림을 중지합니다.
  Future<void> stop() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  /// record plugin recorder 인스턴스를 해제합니다.
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
