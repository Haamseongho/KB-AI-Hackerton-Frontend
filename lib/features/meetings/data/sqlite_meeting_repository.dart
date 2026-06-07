import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/meeting_repository.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_type.dart';
import '../domain/recording_asset.dart';
import '../domain/transcript_segment.dart';

/// 앱 재시작 후에도 회의방, transcript, recording metadata를 유지하는 SQLite 저장소입니다.
///
/// 데모 흐름에서 필요한 데이터를 우선 보존합니다. 실제 오디오 파일과 transcript txt는
/// 파일 시스템에 저장하고, 이 저장소에는 파일 경로와 검색 가능한 metadata를 남깁니다.
class SqliteMeetingRepository implements MeetingRepository {
  SqliteMeetingRepository({Database? database}) : _database = database;

  static const _databaseName = 'voice_doc_flutter.db';
  static const _databaseVersion = 2;

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final path = p.join(await getDatabasesPath(), _databaseName);
    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    _database = db;
    return db;
  }

  @override
  Future<List<MeetingRoom>> listRooms({String query = ''}) async {
    final db = await _db;
    final normalized = query.trim().toLowerCase();
    final rows = await db.query('meetings', orderBy: 'updated_at DESC');
    final rooms = <MeetingRoom>[];

    for (final row in rows) {
      final room = await _roomFromRow(db, row);
      if (normalized.isEmpty ||
          room.title.toLowerCase().contains(normalized) ||
          room.meetingId.toLowerCase().contains(normalized) ||
          _dateText(room.createdAt).contains(normalized) ||
          room.status.value.toLowerCase().contains(normalized)) {
        rooms.add(room);
      }
    }

    return List.unmodifiable(rooms);
  }

  @override
  Future<MeetingRoom> saveRoom(MeetingRoom room) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        'meetings',
        _meetingRow(room),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        'transcript_segments',
        where: 'local_id = ?',
        whereArgs: [room.localId],
      );
      for (var index = 0; index < room.segments.length; index += 1) {
        await txn.insert(
          'transcript_segments',
          _segmentRow(room.localId, room.segments[index], index),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return room;
  }

  @override
  Future<void> deleteRoom(String localId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'transcript_segments',
        where: 'local_id = ?',
        whereArgs: [localId],
      );
      await txn.delete('meetings', where: 'local_id = ?', whereArgs: [localId]);
    });
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE meetings (
        local_id TEXT PRIMARY KEY,
        meeting_id TEXT NOT NULL,
        backend_id TEXT,
        title TEXT NOT NULL,
        meeting_type TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        notes TEXT,
        summary TEXT,
        partial_transcript TEXT,
        auto_scroll INTEGER NOT NULL,
        stream_session_id TEXT,
        stream_segment_count INTEGER NOT NULL,
        transcript_file_path TEXT,
        minutes_json_s3_key TEXT,
        minutes_markdown_s3_key TEXT,
        pdf_s3_key TEXT,
        uploaded_at TEXT,
        recording_file_name TEXT,
        recording_file_path TEXT,
        recording_content_type TEXT,
        recording_duration_ms INTEGER,
        realtime_audio_encoding TEXT,
        realtime_sample_rate INTEGER,
        realtime_channels INTEGER,
        audio_s3_key TEXT,
        transcript_s3_key TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transcript_segments (
        id TEXT NOT NULL,
        local_id TEXT NOT NULL,
        segment_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        speaker TEXT,
        started_at_ms INTEGER NOT NULL,
        ended_at_ms INTEGER NOT NULL,
        confidence_score REAL,
        is_low_confidence INTEGER NOT NULL DEFAULT 0,
        is_final INTEGER NOT NULL,
        PRIMARY KEY (local_id, id),
        FOREIGN KEY (local_id) REFERENCES meetings(local_id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_meetings_search ON meetings(title, meeting_id, status, created_at)',
    );
  }

  /// 기존 설치 기기의 DB에도 최신 backend transcript metadata 컬럼을 추가합니다.
  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE transcript_segments ADD COLUMN confidence_score REAL',
      );
      await db.execute(
        'ALTER TABLE transcript_segments ADD COLUMN is_low_confidence INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Map<String, Object?> _meetingRow(MeetingRoom room) {
    final recording = room.recording;
    return {
      'local_id': room.localId,
      'meeting_id': room.meetingId,
      'backend_id': room.backendId,
      'title': room.title,
      'meeting_type': room.meetingType.value,
      'status': room.status.value,
      'created_at': room.createdAt.toIso8601String(),
      'updated_at': room.updatedAt.toIso8601String(),
      'notes': room.notes,
      'summary': room.summary,
      'partial_transcript': room.partialTranscript,
      'auto_scroll': room.autoScroll ? 1 : 0,
      'stream_session_id': room.streamSessionId,
      'stream_segment_count': room.streamSegmentCount,
      'transcript_file_path': room.transcriptFilePath,
      'minutes_json_s3_key': room.minutesJsonS3Key,
      'minutes_markdown_s3_key': room.minutesMarkdownS3Key,
      'pdf_s3_key': room.pdfS3Key,
      'uploaded_at': room.uploadedAt?.toIso8601String(),
      'recording_file_name': recording?.fileName,
      'recording_file_path': recording?.filePath,
      'recording_content_type': recording?.contentType,
      'recording_duration_ms': recording?.durationMs,
      'realtime_audio_encoding': recording?.realtimeAudioEncoding,
      'realtime_sample_rate': recording?.realtimeSampleRate,
      'realtime_channels': recording?.realtimeChannels,
      'audio_s3_key': recording?.audioS3Key,
      'transcript_s3_key': recording?.transcriptS3Key,
    };
  }

  Map<String, Object?> _segmentRow(
    String localId,
    TranscriptSegment segment,
    int index,
  ) {
    return {
      'id': segment.id,
      'local_id': localId,
      'segment_index': index,
      'text': segment.text,
      'speaker': segment.speaker,
      'started_at_ms': segment.startedAt.inMilliseconds,
      'ended_at_ms': segment.endedAt.inMilliseconds,
      'confidence_score': segment.confidenceScore,
      'is_low_confidence': segment.isLowConfidence ? 1 : 0,
      'is_final': segment.isFinal ? 1 : 0,
    };
  }

  Future<MeetingRoom> _roomFromRow(
    Database db,
    Map<String, Object?> row,
  ) async {
    final localId = row['local_id']! as String;
    final segmentRows = await db.query(
      'transcript_segments',
      where: 'local_id = ?',
      whereArgs: [localId],
      orderBy: 'segment_index ASC',
    );

    return MeetingRoom(
      localId: localId,
      meetingId: row['meeting_id']! as String,
      backendId: row['backend_id'] as String?,
      title: row['title']! as String,
      meetingType: _meetingTypeFromValue(row['meeting_type'] as String?),
      status: MeetingStatus.fromJson(row['status'] as String?),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      notes: row['notes'] as String?,
      recording: _recordingFromRow(row),
      summary: row['summary'] as String?,
      segments: segmentRows.map(_segmentFromRow).toList(growable: false),
      partialTranscript: row['partial_transcript'] as String?,
      autoScroll: (row['auto_scroll'] as int? ?? 1) == 1,
      streamSessionId: row['stream_session_id'] as String?,
      streamSegmentCount: row['stream_segment_count'] as int? ?? 0,
      transcriptFilePath: row['transcript_file_path'] as String?,
      minutesJsonS3Key: row['minutes_json_s3_key'] as String?,
      minutesMarkdownS3Key: row['minutes_markdown_s3_key'] as String?,
      pdfS3Key: row['pdf_s3_key'] as String?,
      uploadedAt: _dateTimeOrNull(row['uploaded_at'] as String?),
    );
  }

  RecordingAsset? _recordingFromRow(Map<String, Object?> row) {
    final fileName = row['recording_file_name'] as String?;
    final filePath = row['recording_file_path'] as String?;
    final contentType = row['recording_content_type'] as String?;
    if (fileName == null || filePath == null || contentType == null) {
      return null;
    }

    return RecordingAsset(
      fileName: fileName,
      filePath: filePath,
      contentType: contentType,
      durationMs: row['recording_duration_ms'] as int? ?? 0,
      realtimeAudioEncoding: row['realtime_audio_encoding'] as String? ?? 'pcm',
      realtimeSampleRate: row['realtime_sample_rate'] as int? ?? 16000,
      realtimeChannels: row['realtime_channels'] as int? ?? 1,
      audioS3Key: row['audio_s3_key'] as String?,
      transcriptS3Key: row['transcript_s3_key'] as String?,
    );
  }

  TranscriptSegment _segmentFromRow(Map<String, Object?> row) {
    return TranscriptSegment(
      id: row['id']! as String,
      text: row['text']! as String,
      speaker: row['speaker'] as String?,
      startedAt: Duration(milliseconds: row['started_at_ms']! as int),
      endedAt: Duration(milliseconds: row['ended_at_ms']! as int),
      isFinal: (row['is_final'] as int? ?? 1) == 1,
      confidenceScore: _doubleOrNull(row['confidence_score']),
      isLowConfidence: (row['is_low_confidence'] as int? ?? 0) == 1,
    );
  }

  MeetingType _meetingTypeFromValue(String? value) {
    return MeetingType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => MeetingType.unknown,
    );
  }

  DateTime? _dateTimeOrNull(String? value) {
    return value == null ? null : DateTime.tryParse(value);
  }

  double? _doubleOrNull(Object? value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    return null;
  }

  String _dateText(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
