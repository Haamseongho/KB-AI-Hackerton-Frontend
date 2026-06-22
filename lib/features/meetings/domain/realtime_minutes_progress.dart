class RealtimeMinutesProgress {
  const RealtimeMinutesProgress({
    this.statusCode,
    this.percent,
    this.step,
    this.message,
    this.updatedAt,
    this.completed = false,
    this.failed = false,
  });

  final int? statusCode;
  final int? percent;
  final String? step;
  final String? message;
  final DateTime? updatedAt;
  final bool completed;
  final bool failed;

  bool get isVisible {
    return failed ||
        completed ||
        (percent != null && percent! > 0 && percent! < 100) ||
        step == 'requested';
  }

  bool get isProcessing => !completed && !failed && isVisible;

  int get safePercent {
    final value = percent ?? 0;
    return value.clamp(0, 100);
  }

  static RealtimeMinutesProgress? fromJson(Map<String, dynamic> json) {
    final progress = RealtimeMinutesProgress(
      statusCode: _intValue(json['realtime_status_code']),
      percent: _intValue(json['progress_percent']),
      step: json['progress_step'] as String?,
      message: json['progress_message'] as String?,
      updatedAt: _dateTimeValue(json['progress_updated_at']),
      completed: json['completed'] == true,
      failed: json['failed'] == true,
    );
    return progress.isVisible || progress.statusCode != null ? progress : null;
  }

  static int? _intValue(Object? value) {
    return switch (value) {
      int() => value,
      num() => value.toInt(),
      String() => int.tryParse(value),
      _ => null,
    };
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
