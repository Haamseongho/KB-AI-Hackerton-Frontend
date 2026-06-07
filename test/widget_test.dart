import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_room.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_type.dart';
import 'package:kb_ai_hackerton_frontend/main.dart';

void main() {
  testWidgets('shows realtime meeting rooms workflow', (tester) async {
    await tester.pumpWidget(
      VoiceDocApp(repository: InMemoryMeetingRepository()),
    );
    await tester.pump();

    expect(find.text('회의방'), findsOneWidget);
    expect(find.text('새 회의방'), findsOneWidget);
    expect(find.text('아직 생성된 회의방이 없습니다.'), findsOneWidget);
    expect(find.textContaining('PCM 오디오'), findsOneWidget);
  });

  testWidgets('deletes a meeting room from the device menu', (tester) async {
    final now = DateTime(2026, 6, 7);
    final repository = InMemoryMeetingRepository(
      rooms: [
        MeetingRoom(
          localId: 'local-1',
          meetingId: 'MTG-20260607-001',
          title: '삭제할 회의',
          meetingType: MeetingType.unknown,
          status: MeetingStatus.ready,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    await tester.pumpWidget(VoiceDocApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('삭제할 회의'), findsOneWidget);
    await tester.tap(find.byTooltip('회의방 옵션'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기기에서 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('기기에서 삭제하시겠습니까?'), findsOneWidget);
    expect(find.textContaining('백엔드에 생성된 회의 데이터'), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('삭제할 회의'), findsNothing);
    expect(find.text('아직 생성된 회의방이 없습니다.'), findsOneWidget);
  });
}
