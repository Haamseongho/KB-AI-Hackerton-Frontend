enum MeetingWorkflow {
  realtime('realtime', '실시간 STT'),
  batch('batch', '배치 전사');

  const MeetingWorkflow(this.value, this.label);

  final String value;
  final String label;

  static MeetingWorkflow fromJson(String? value) {
    return MeetingWorkflow.values.firstWhere(
      (workflow) => workflow.value == value,
      orElse: () => MeetingWorkflow.realtime,
    );
  }
}
