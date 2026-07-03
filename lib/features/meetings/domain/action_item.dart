import 'speaker_label.dart';

class ActionItem {
  const ActionItem({
    this.owner,
    required this.task,
    this.dueDate,
    this.dueDateResolved,
    this.calendarEventId,
    this.calendarAddedAt,
  });

  final String? owner;
  final String task;
  final String? dueDate;
  final String? dueDateResolved;
  final String? calendarEventId;
  final DateTime? calendarAddedAt;

  bool get isAddedToCalendar => calendarAddedAt != null;

  bool get hasResolvedDueDate {
    final value = dueDateResolved?.trim();
    return value != null && value.isNotEmpty;
  }

  bool get hasDueDate {
    final value = dueDate?.trim();
    return value != null && value.isNotEmpty;
  }

  bool get hasCalendarCandidateDate => hasResolvedDueDate || hasDueDate;

  String get displayOwner {
    return displaySpeakerLabel(owner, fallback: '담당자 미정');
  }

  String get displayDueDate {
    final resolved = dueDateResolved?.trim();
    if (resolved != null && resolved.isNotEmpty) return resolved;
    final original = dueDate?.trim();
    return original == null || original.isEmpty ? '미정' : original;
  }

  DateTime? get resolvedDate {
    final value = dueDateResolved?.trim();
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  ActionItem copyWith({
    String? owner,
    String? task,
    String? dueDate,
    String? dueDateResolved,
    String? calendarEventId,
    DateTime? calendarAddedAt,
  }) {
    return ActionItem(
      owner: owner ?? this.owner,
      task: task ?? this.task,
      dueDate: dueDate ?? this.dueDate,
      dueDateResolved: dueDateResolved ?? this.dueDateResolved,
      calendarEventId: calendarEventId ?? this.calendarEventId,
      calendarAddedAt: calendarAddedAt ?? this.calendarAddedAt,
    );
  }

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      owner: json['owner']?.toString(),
      task: (json['task'] ?? json['action'] ?? '').toString(),
      dueDate: json['due_date']?.toString(),
      dueDateResolved: json['due_date_resolved']?.toString(),
      calendarEventId: json['calendar_event_id']?.toString(),
      calendarAddedAt: _dateTimeOrNull(json['calendar_added_at']?.toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (owner != null) 'owner': owner,
      'task': task,
      if (dueDate != null) 'due_date': dueDate,
      if (dueDateResolved != null) 'due_date_resolved': dueDateResolved,
      if (calendarEventId != null) 'calendar_event_id': calendarEventId,
      if (calendarAddedAt != null)
        'calendar_added_at': calendarAddedAt!.toIso8601String(),
    };
  }

  static DateTime? _dateTimeOrNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
