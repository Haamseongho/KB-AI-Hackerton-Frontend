import '../domain/meeting_repository.dart';
import '../domain/meeting_room.dart';
import '../domain/meeting_status.dart';
import '../domain/meeting_type.dart';
import '../domain/recording_asset.dart';
import '../domain/transcript_segment.dart';

class InMemoryMeetingRepository implements MeetingRepository {
  InMemoryMeetingRepository({List<MeetingRoom>? rooms}) : _rooms = rooms ?? [];

  factory InMemoryMeetingRepository.seeded() {
    final now = DateTime(2026, 5, 21, 14, 57);
    return InMemoryMeetingRepository(
      rooms: [
        MeetingRoom(
          localId: 'local-1',
          meetingId: 'MTG-20260521-006',
          title: 'REALTIME_TEST',
          meetingType: MeetingType.general,
          status: MeetingStatus.paused,
          createdAt: now,
          updatedAt: now,
          notes: '녹음 -> 실시간',
          recording: const RecordingAsset(
            fileName: 'REALTIME_TEST_20260521.m4a',
            filePath: '/local/REALTIME_TEST_20260521.m4a',
            contentType: 'audio/mp4',
            durationMs: 59000,
            realtimeAudioEncoding: 'pcm_s16le',
            realtimeSampleRate: 16000,
            realtimeChannels: 1,
          ),
          segments: const [
            TranscriptSegment(
              id: 'seg-1',
              text: '자를 시작하겠습니다.',
              startedAt: Duration(seconds: 1),
              endedAt: Duration(seconds: 3),
              isFinal: true,
              speaker: 'Speaker 1',
            ),
            TranscriptSegment(
              id: 'seg-2',
              text: '녹음.',
              startedAt: Duration(seconds: 4),
              endedAt: Duration(seconds: 5),
              isFinal: true,
              speaker: 'Speaker 1',
            ),
          ],
        ),
        MeetingRoom(
          localId: 'local-2',
          meetingId: 'MTG-20260521-003',
          title: 'hi-yoa',
          meetingType: MeetingType.general,
          status: MeetingStatus.completed,
          createdAt: now.subtract(const Duration(hours: 1)),
          updatedAt: now.subtract(const Duration(minutes: 30)),
        ),
      ],
    );
  }

  final List<MeetingRoom> _rooms;

  @override
  Future<List<MeetingRoom>> listRooms({String query = ''}) async {
    final normalized = query.trim().toLowerCase();
    final rooms = normalized.isEmpty
        ? _rooms
        : _rooms.where((room) {
            return room.title.toLowerCase().contains(normalized) ||
                room.meetingId.toLowerCase().contains(normalized);
          }).toList();

    return List.unmodifiable(rooms);
  }

  @override
  Future<MeetingRoom> saveRoom(MeetingRoom room) async {
    final index = _rooms.indexWhere((item) => item.localId == room.localId);
    if (index == -1) {
      _rooms.insert(0, room);
    } else {
      _rooms[index] = room;
    }
    return room;
  }
}
