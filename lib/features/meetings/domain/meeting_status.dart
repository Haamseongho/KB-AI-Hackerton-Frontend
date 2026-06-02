enum MeetingStatus {
  ready('ready', '준비'),
  created('created', '생성됨'),
  uploadUrlIssued('upload_url_issued', '업로드 준비'),
  uploading('uploading', '처리 중'),
  uploaded('uploaded', '업로드 완료'),
  queued('queued', '대기 중'),
  orchestrationStarting('orchestration_starting', '시작 중'),
  orchestrationStarted('orchestration_started', '진행 중'),
  recording('recording', '녹음 중'),
  paused('paused', '일시정지'),
  transcribing('transcribing', '변환 중'),
  transcriptionCompleted('transcription_completed', '변환 완료'),
  summaryQueued('summary_queued', '요약 대기'),
  summarizing('summarizing', '요약 중'),
  generatingMinutes('generating_minutes', '회의록 생성 중'),
  completed('completed', '완료'),
  failed('failed', '실패');

  const MeetingStatus(this.value, this.label);

  final String value;
  final String label;

  static MeetingStatus fromJson(String? value) {
    return MeetingStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => MeetingStatus.ready,
    );
  }
}
