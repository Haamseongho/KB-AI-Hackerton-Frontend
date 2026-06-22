import 'transcript_segment.dart';

sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

class TranscriptionStatusEvent extends TranscriptionEvent {
  const TranscriptionStatusEvent({
    required this.status,
    required this.message,
    this.realtimeStatusCode,
  });

  final String status;
  final String message;
  final int? realtimeStatusCode;
}

class PartialTranscriptEvent extends TranscriptionEvent {
  const PartialTranscriptEvent({required this.text});

  final String text;
}

class FinalTranscriptEvent extends TranscriptionEvent {
  const FinalTranscriptEvent({required this.segment});

  final TranscriptSegment segment;
}

class TranscriptionErrorEvent extends TranscriptionEvent {
  const TranscriptionErrorEvent({required this.message});

  final String message;
}
