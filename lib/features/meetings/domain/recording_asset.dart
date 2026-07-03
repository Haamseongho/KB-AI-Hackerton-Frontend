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
    this.fileSizeBytes,
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
  final int? fileSizeBytes;

  RecordingAsset copyWith({
    String? fileName,
    String? filePath,
    String? contentType,
    int? durationMs,
    String? realtimeAudioEncoding,
    int? realtimeSampleRate,
    int? realtimeChannels,
    String? audioS3Key,
    String? transcriptS3Key,
    int? fileSizeBytes,
  }) {
    return RecordingAsset(
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      contentType: contentType ?? this.contentType,
      durationMs: durationMs ?? this.durationMs,
      realtimeAudioEncoding:
          realtimeAudioEncoding ?? this.realtimeAudioEncoding,
      realtimeSampleRate: realtimeSampleRate ?? this.realtimeSampleRate,
      realtimeChannels: realtimeChannels ?? this.realtimeChannels,
      audioS3Key: audioS3Key ?? this.audioS3Key,
      transcriptS3Key: transcriptS3Key ?? this.transcriptS3Key,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }
}
