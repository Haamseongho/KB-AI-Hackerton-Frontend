import 'dart:typed_data';

import 'package:record/record.dart';

import '../../../core/errors/app_exception.dart';

class RealtimeAudioStreamingService {
  RealtimeAudioStreamingService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<Stream<Uint8List>> startPcmStream({
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    final supported = await _recorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    if (!supported) {
      throw const AppException('현재 기기에서 실시간 PCM 녹음 스트림을 지원하지 않습니다.');
    }

    return _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
        streamBufferSize: 4096,
      ),
    );
  }

  Future<void> stop() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
