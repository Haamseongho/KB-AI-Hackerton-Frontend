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

  Future<Map<String, dynamic>> createMinutesFromRealtime(
    String backendMeetingId, {
    List<Map<String, String?>>? segments,
  }) {
    return _client.postJson(
      '/meetings/$backendMeetingId/minutes-from-realtime',
      body: segments == null ? null : {'segments': segments},
    );
  }
}
