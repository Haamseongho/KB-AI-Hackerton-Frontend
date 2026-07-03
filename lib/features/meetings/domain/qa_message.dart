import 'speaker_label.dart';

enum QaMessageRole {
  user('user'),
  assistant('assistant');

  const QaMessageRole(this.value);

  final String value;

  static QaMessageRole fromJson(String? value) {
    return QaMessageRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => QaMessageRole.assistant,
    );
  }
}

class QaEvidence {
  const QaEvidence({
    required this.speaker,
    required this.quote,
    this.timestamp,
  });

  final String speaker;
  final String quote;
  final String? timestamp;

  String get displaySpeaker => displaySpeakerLabel(speaker);

  factory QaEvidence.fromJson(Map<String, dynamic> json) {
    return QaEvidence(
      speaker: (json['speaker'] ?? '').toString(),
      timestamp: json['timestamp']?.toString(),
      quote: (json['quote'] ?? '').toString(),
    );
  }
}

class QaMessage {
  const QaMessage({
    required this.id,
    required this.seq,
    required this.role,
    required this.content,
    required this.createdAt,
    this.answerable,
    this.grounding,
    this.displayType,
    this.confidence,
    this.groundingRatio,
    this.droppedEvidenceCount,
    this.evidence = const [],
    this.mindmapUrl,
  });

  final String id;
  final int seq;
  final QaMessageRole role;
  final String content;
  final String createdAt;
  final bool? answerable;
  final String? grounding;
  final String? displayType;
  final String? confidence;
  final double? groundingRatio;
  final int? droppedEvidenceCount;
  final List<QaEvidence> evidence;
  final String? mindmapUrl;

  bool get isUser => role == QaMessageRole.user;
  bool get isRejected => role == QaMessageRole.assistant && answerable == false;
  bool get isMindmap => displayType == 'mindmap';
  bool get hasMindmapImage => (mindmapUrl ?? '').trim().isNotEmpty;

  factory QaMessage.localUser(String content) {
    final now = DateTime.now();
    return QaMessage(
      id: 'local-user-${now.microsecondsSinceEpoch}',
      seq: -1,
      role: QaMessageRole.user,
      content: content,
      createdAt: _localCreatedAt(now),
    );
  }

  factory QaMessage.localAssistant(String content) {
    final now = DateTime.now();
    return QaMessage(
      id: 'local-assistant-${now.microsecondsSinceEpoch}',
      seq: -1,
      role: QaMessageRole.assistant,
      content: content,
      createdAt: _localCreatedAt(now),
      answerable: false,
      displayType: 'local',
      confidence: 'low',
    );
  }

  factory QaMessage.fromAnswerJson(Map<String, dynamic> json) {
    return QaMessage(
      id: (json['message_id'] ?? '').toString(),
      seq: _intOrZero(json['seq']),
      role: QaMessageRole.assistant,
      content: (json['answer'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      answerable: json['answerable'] as bool?,
      grounding: json['grounding']?.toString(),
      displayType: json['display_type']?.toString(),
      confidence: json['confidence']?.toString(),
      groundingRatio: _doubleOrNull(json['grounding_ratio']),
      droppedEvidenceCount: _intOrNull(json['dropped_evidence_count']),
      evidence: _evidenceList(json['evidence']),
      mindmapUrl: json['mindmap_url']?.toString(),
    );
  }

  factory QaMessage.fromHistoryJson(Map<String, dynamic> json) {
    return QaMessage(
      id: (json['id'] ?? '').toString(),
      seq: _intOrZero(json['seq']),
      role: QaMessageRole.fromJson(json['role']?.toString()),
      content: (json['content'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
      answerable: json['answerable'] as bool?,
      grounding: json['grounding']?.toString(),
      displayType: json['display_type']?.toString(),
      confidence: json['confidence']?.toString(),
      groundingRatio: _doubleOrNull(json['grounding_ratio']),
      evidence: _evidenceList(json['evidence']),
      mindmapUrl: json['mindmap_url']?.toString(),
    );
  }

  static List<QaEvidence> _evidenceList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => QaEvidence.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.quote.trim().isNotEmpty)
        .toList(growable: false);
  }

  static int _intOrZero(Object? value) => _intOrNull(value) ?? 0;

  static int? _intOrNull(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _doubleOrNull(Object? value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return double.tryParse(value?.toString() ?? '');
  }

  static String _localCreatedAt(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
  }
}
