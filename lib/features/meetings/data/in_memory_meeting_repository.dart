import '../domain/meeting_repository.dart';
import '../domain/meeting_room.dart';

class InMemoryMeetingRepository implements MeetingRepository {
  InMemoryMeetingRepository({List<MeetingRoom>? rooms}) : _rooms = rooms ?? [];

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
