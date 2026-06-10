import 'meeting_room.dart';

abstract interface class MeetingRepository {
  Future<List<MeetingRoom>> listRooms({String query = ''});

  Future<MeetingRoom?> getRoom(String localId);

  Future<MeetingRoom> saveRoom(MeetingRoom room);

  Future<void> deleteRoom(String localId);
}
