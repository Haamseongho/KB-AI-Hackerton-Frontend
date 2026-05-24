enum MeetingStatus {
  ready('ready', 'Ready'),
  recording('recording', 'Recording'),
  paused('paused', 'Paused'),
  transcribing('transcribing', 'Transcribing'),
  transcriptionCompleted('transcription_completed', 'Completed'),
  summaryQueued('summary_queued', 'Summary queued'),
  summarizing('summarizing', 'Summarizing'),
  completed('completed', 'Completed'),
  uploaded('uploaded', 'Uploaded'),
  failed('failed', 'Failed');

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
