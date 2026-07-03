import 'meeting_status.dart';

enum BatchTranscriptionStatus {
  queued(1, '작업 대기 중', MeetingStatus.queued),
  uploaded(2, '업로드 완료', MeetingStatus.uploaded),
  transcribing(3, '전사 중', MeetingStatus.transcribing),
  summarizing(4, '요약 중', MeetingStatus.summarizing),
  completed(5, '완료', MeetingStatus.completed),
  failed(6, '실패', MeetingStatus.failed);

  const BatchTranscriptionStatus(this.code, this.label, this.meetingStatus);

  final int code;
  final String label;
  final MeetingStatus meetingStatus;

  static BatchTranscriptionStatus? fromCode(Object? value) {
    final code = switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value),
      _ => null,
    };
    if (code == null) return null;

    for (final status in BatchTranscriptionStatus.values) {
      if (status.code == code) return status;
    }
    return null;
  }
}
