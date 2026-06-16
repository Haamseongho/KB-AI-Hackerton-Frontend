import 'dart:typed_data';

import '../../../core/network/api_client.dart';
import '../domain/meeting_type.dart';

class MeetingApi {
  MeetingApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<Map<String, dynamic>> createMeetingRoom({
    required String title,
    required MeetingType meetingType,
    String? notes,
  }) {
    return _client.postJson(
      '/meetings',
      body: {'title': title, 'meeting_type': meetingType.value},
    );
  }

  Future<Map<String, dynamic>> startMeetingPipeline(String backendMeetingId) {
    return _client.postJson('/meetings/$backendMeetingId/start');
  }

  Future<Map<String, dynamic>> getMeeting(String backendMeetingId) {
    return _client.getJson('/meetings/$backendMeetingId');
  }

  Future<Map<String, dynamic>> getBatchStatus(String backendMeetingId) {
    return _client.getJson('/meetings/$backendMeetingId/batch-status');
  }

  Future<Map<String, dynamic>> getMeetingResult(String backendMeetingId) {
    return _client.getJson('/meetings/$backendMeetingId/result');
  }

  Future<Map<String, dynamic>> getJob(String jobId) {
    return _client.getJson('/jobs/$jobId');
  }

  Future<Map<String, dynamic>> requestAudioUploadUrl(
    String backendMeetingId, {
    String fileExtension = 'm4a',
    String contentType = 'audio/mp4',
  }) {
    return _client.postJson(
      '/meetings/$backendMeetingId/upload-url',
      body: {'file_extension': fileExtension, 'content_type': contentType},
    );
  }

  Future<void> uploadAudioBytes(
    String uploadUrl, {
    required Uint8List bytes,
    required String contentType,
  }) {
    return _client.putBytes(uploadUrl, bytes: bytes, contentType: contentType);
  }

  Future<void> uploadAudioFile(
    String uploadUrl, {
    required String filePath,
    required String contentType,
  }) {
    return _client.putFile(
      uploadUrl,
      filePath: filePath,
      contentType: contentType,
    );
  }

  Future<Map<String, dynamic>> confirmAudioUpload(String backendMeetingId) {
    return _client.postJson('/meetings/$backendMeetingId/upload-confirm');
  }

  Future<Uint8List> downloadRealtimeTranscript(String backendMeetingId) {
    return _client.getPathBytes(
      '/meetings/$backendMeetingId/transcript/realtime',
    );
  }

  Future<Uint8List> downloadBatchTranscript(String backendMeetingId) {
    return _client.getPathBytes('/meetings/$backendMeetingId/transcript/batch');
  }

  Future<Map<String, dynamic>> createMinutesFromRealtime(
    String backendMeetingId, {
    List<Map<String, Object?>>? segments,
  }) {
    return _client.postJson(
      '/meetings/$backendMeetingId/minutes-from-realtime',
      body: segments == null ? null : {'segments': segments},
    );
  }

  /// S3 회의록 PDF를 내려받을 수 있는 짧은 만료 시간의 URL을 요청합니다.
  Future<Map<String, dynamic>> requestPdfDownloadUrl(String backendMeetingId) {
    return _client.getJson('/meetings/$backendMeetingId/pdf-download-url');
  }

  /// S3 회의록 DOCX를 내려받을 수 있는 짧은 만료 시간의 URL을 요청합니다.
  Future<Map<String, dynamic>> requestDocxDownloadUrl(String backendMeetingId) {
    return _client.getJson('/meetings/$backendMeetingId/docx-download-url');
  }

  /// 백엔드에 저장된 realtime transcript segment를 삭제합니다.
  Future<Map<String, dynamic>> deleteTranscriptSegments(
    String backendMeetingId,
  ) {
    return _client.deleteJson(
      '/meetings/$backendMeetingId/transcript-segments',
    );
  }

  /// S3에 생성된 JSON, Markdown, PDF 회의록 산출물을 삭제합니다.
  Future<Map<String, dynamic>> deleteMeetingArtifacts(String backendMeetingId) {
    return _client.deleteJson('/meetings/$backendMeetingId/artifacts');
  }

  Future<List<int>> downloadFileBytes(String url) async {
    return _client.getBytes(url);
  }
}
