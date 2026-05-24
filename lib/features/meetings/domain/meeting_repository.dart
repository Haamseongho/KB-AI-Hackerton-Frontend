import 'meeting_room.dart';

abstract interface class MeetingRepository {
  Future<List<MeetingRoom>> listRooms({String query = ''});

  Future<MeetingRoom> saveRoom(MeetingRoom room);
}
