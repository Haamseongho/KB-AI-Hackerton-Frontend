import 'batch_transcription_status.dart';
import 'meeting_status.dart';
import 'meeting_type.dart';
import 'meeting_workflow.dart';
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
    this.workflow = MeetingWorkflow.realtime,
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
    this.docxS3Key,
    this.uploadedAt,
    this.batchJobId,
    this.batchStatus,
    this.batchErrorMessage,
    this.decisions = const [],
    this.openIssues = const [],
    this.actionItems = const [],
  });

  final String localId;
  final String meetingId;
  final String? backendId;
  final String title;
  final MeetingType meetingType;
  final MeetingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final MeetingWorkflow workflow;
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
  final String? docxS3Key;
  final DateTime? uploadedAt;
  final String? batchJobId;
  final BatchTranscriptionStatus? batchStatus;
  final String? batchErrorMessage;
  final List<String> decisions;
  final List<String> openIssues;
  final List<Map<String, dynamic>> actionItems;

  MeetingRoom copyWith({
    String? localId,
    String? meetingId,
    String? backendId,
    String? title,
    MeetingType? meetingType,
    MeetingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    MeetingWorkflow? workflow,
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
    String? docxS3Key,
    DateTime? uploadedAt,
    String? batchJobId,
    BatchTranscriptionStatus? batchStatus,
    bool clearBatchStatus = false,
    String? batchErrorMessage,
    bool clearBatchError = false,
    List<String>? decisions,
    List<String>? openIssues,
    List<Map<String, dynamic>>? actionItems,
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
      workflow: workflow ?? this.workflow,
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
      docxS3Key: docxS3Key ?? this.docxS3Key,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      batchJobId: batchJobId ?? this.batchJobId,
      batchStatus: clearBatchStatus ? null : batchStatus ?? this.batchStatus,
      batchErrorMessage: clearBatchError
          ? null
          : batchErrorMessage ?? this.batchErrorMessage,
      decisions: decisions ?? this.decisions,
      openIssues: openIssues ?? this.openIssues,
      actionItems: actionItems ?? this.actionItems,
    );
  }
}
