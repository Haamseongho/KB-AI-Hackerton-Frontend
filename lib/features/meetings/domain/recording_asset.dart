class RecordingAsset {
  const RecordingAsset({
    required this.fileName,
    required this.filePath,
    required this.contentType,
    required this.durationMs,
    required this.realtimeAudioEncoding,
    required this.realtimeSampleRate,
    required this.realtimeChannels,
    this.audioS3Key,
    this.transcriptS3Key,
  });

  final String fileName;
  final String filePath;
  final String contentType;
  final int durationMs;
  final String realtimeAudioEncoding;
  final int realtimeSampleRate;
  final int realtimeChannels;
  final String? audioS3Key;
  final String? transcriptS3Key;
}
