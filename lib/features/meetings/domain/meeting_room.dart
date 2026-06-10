import 'meeting_status.dart';
import 'meeting_type.dart';
import 'recording_asset.dart';
import 'transcript_segment.dart';

class MeetingRoom {
  const MeetingRoom({
    required this.localId,
    required this.meetingId,
    required this.title,
    required this.meetingType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.backendId,
    this.notes,
    this.recording,
    this.summary,
    this.segments = const [],
    this.partialTranscript,
    this.autoScroll = true,
    this.streamSessionId,
    this.streamSegmentCount = 0,
    this.transcriptFilePath,
    this.minutesJsonS3Key,
    this.minutesMarkdownS3Key,
    this.pdfS3Key,
    this.uploadedAt,
    this.batchJobId,
    this.batchErrorMessage,
  });

  final String localId;
  final String meetingId;
  final String? backendId;
  final String title;
  final MeetingType meetingType;
  final MeetingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;
  final RecordingAsset? recording;
  final String? summary;
  final List<TranscriptSegment> segments;
  final String? partialTranscript;
  final bool autoScroll;
  final String? streamSessionId;
  final int streamSegmentCount;
  final String? transcriptFilePath;
  final String? minutesJsonS3Key;
  final String? minutesMarkdownS3Key;
  final String? pdfS3Key;
  final DateTime? uploadedAt;
  final String? batchJobId;
  final String? batchErrorMessage;

  MeetingRoom copyWith({
    String? localId,
    String? meetingId,
    String? backendId,
    String? title,
    MeetingType? meetingType,
    MeetingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? notes,
    RecordingAsset? recording,
    String? summary,
    List<TranscriptSegment>? segments,
    String? partialTranscript,
    bool clearPartialTranscript = false,
    bool? autoScroll,
    String? streamSessionId,
    int? streamSegmentCount,
    String? transcriptFilePath,
    String? minutesJsonS3Key,
    String? minutesMarkdownS3Key,
    String? pdfS3Key,
    DateTime? uploadedAt,
    String? batchJobId,
    String? batchErrorMessage,
    bool clearBatchError = false,
  }) {
    return MeetingRoom(
      localId: localId ?? this.localId,
      meetingId: meetingId ?? this.meetingId,
      backendId: backendId ?? this.backendId,
      title: title ?? this.title,
      meetingType: meetingType ?? this.meetingType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      recording: recording ?? this.recording,
      summary: summary ?? this.summary,
      segments: segments ?? this.segments,
      partialTranscript: clearPartialTranscript
          ? null
          : partialTranscript ?? this.partialTranscript,
      autoScroll: autoScroll ?? this.autoScroll,
      streamSessionId: streamSessionId ?? this.streamSessionId,
      streamSegmentCount: streamSegmentCount ?? this.streamSegmentCount,
      transcriptFilePath: transcriptFilePath ?? this.transcriptFilePath,
      minutesJsonS3Key: minutesJsonS3Key ?? this.minutesJsonS3Key,
      minutesMarkdownS3Key: minutesMarkdownS3Key ?? this.minutesMarkdownS3Key,
      pdfS3Key: pdfS3Key ?? this.pdfS3Key,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      batchJobId: batchJobId ?? this.batchJobId,
      batchErrorMessage: clearBatchError
          ? null
          : batchErrorMessage ?? this.batchErrorMessage,
    );
  }
}
