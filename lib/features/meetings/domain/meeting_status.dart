enum MeetingStatus {
  ready('ready', 'Ready'),
  created('created', 'Created'),
  uploadUrlIssued('upload_url_issued', 'Upload URL issued'),
  uploaded('uploaded', 'Uploaded'),
  queued('queued', 'Queued'),
  orchestrationStarting('orchestration_starting', 'Starting'),
  orchestrationStarted('orchestration_started', 'Started'),
  recording('recording', 'Recording'),
  paused('paused', 'Paused'),
  transcribing('transcribing', 'Transcribing'),
  transcriptionCompleted('transcription_completed', 'Completed'),
  summaryQueued('summary_queued', 'Summary queued'),
  summarizing('summarizing', 'Summarizing'),
  completed('completed', 'Completed'),
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
