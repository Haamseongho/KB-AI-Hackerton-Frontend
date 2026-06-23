import 'speaker_label.dart';

class TranscriptSegment {
  const TranscriptSegment({
    required this.id,
    required this.text,
    required this.startedAt,
    required this.endedAt,
    required this.isFinal,
    this.speaker,
    this.confidenceScore,
    this.isLowConfidence = false,
  });

  final String id;
  final String text;
  final Duration startedAt;
  final Duration endedAt;
  final bool isFinal;
  final String? speaker;
  final double? confidenceScore;
  final bool isLowConfidence;

  String get displaySpeaker => displaySpeakerLabel(speaker);
}
