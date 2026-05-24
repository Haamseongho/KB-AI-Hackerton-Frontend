import '../../../core/network/api_client.dart';
import '../domain/meeting_type.dart';

class MeetingApi {
  MeetingApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<Map<String, dynamic>> createMeetingRoom({
    required String title,
    required MeetingType meetingType,
    required String storageType,
    String? notes,
  }) {
    return _client.postJson(
      '/meetings',
      body: {
        'title': title,
        'meeting_type': meetingType.value,
        'notes': notes,
        'storage_metadata': {'type': storageType},
      },
    );
  }

  Future<Map<String, dynamic>> requestSummary(String meetingId) {
    return _client.postJson('/meetings/$meetingId/summarize');
  }

  Future<Map<String, dynamic>> requestUploadUrls(String meetingId) {
    return _client.postJson(
      '/meetings/$meetingId/upload-url',
      body: {
        'assets': [
          {
            'asset_type': 'recording',
            'file_extension': 'm4a',
            'content_type': 'audio/mp4',
          },
          {
            'asset_type': 'transcript',
            'file_extension': 'txt',
            'content_type': 'text/plain',
          },
        ],
      },
    );
  }
}
