import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_room.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_type.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/transcript_segment.dart';
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

  testWidgets('deletes a meeting room from the integrated delete menu', (
    tester,
  ) async {
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
    await tester.tap(find.text('회의 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('회의 데이터를 삭제하시겠습니까?'), findsOneWidget);
    expect(find.textContaining('S3 회의록 산출물'), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('삭제할 회의'), findsNothing);
    expect(find.text('아직 생성된 회의방이 없습니다.'), findsOneWidget);
  });

  testWidgets('pins the latest realtime transcript at the top', (tester) async {
    final now = DateTime(2026, 6, 12);
    final repository = InMemoryMeetingRepository(
      rooms: [
        MeetingRoom(
          localId: 'local-live',
          meetingId: 'MTG-20260612-001',
          title: '실시간 전사 테스트',
          meetingType: MeetingType.small,
          status: MeetingStatus.recording,
          createdAt: now,
          updatedAt: now,
          partialTranscript: '현재 말하는 내용',
          segments: const [
            TranscriptSegment(
              id: 'older',
              text: '이전 확정 문장',
              startedAt: Duration(seconds: 1),
              endedAt: Duration(seconds: 2),
              isFinal: true,
            ),
            TranscriptSegment(
              id: 'latest',
              text: '최근 확정 문장',
              startedAt: Duration(seconds: 3),
              endedAt: Duration(seconds: 4),
              isFinal: true,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(VoiceDocApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('실시간 전사 테스트'));
    await tester.pumpAndSettle();

    expect(find.text('테스트'), findsNothing);
    expect(find.text('나가기'), findsOneWidget);
    expect(find.text('자동 스크롤'), findsNothing);
    expect(find.text('최신 대화 상단 고정'), findsOneWidget);

    final partialY = tester.getTopLeft(find.text('현재 말하는 내용')).dy;
    final latestY = tester.getTopLeft(find.text('최근 확정 문장')).dy;
    final olderY = tester.getTopLeft(find.text('이전 확정 문장')).dy;
    expect(partialY, lessThan(latestY));
    expect(latestY, lessThan(olderY));
  });
}
