import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/action_item.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_room.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_status.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_type.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/meeting_workflow.dart';
import 'package:kb_ai_hackerton_frontend/features/meetings/domain/transcript_segment.dart';
import 'package:kb_ai_hackerton_frontend/main.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('shows realtime meeting rooms workflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      VoiceDocApp(repository: InMemoryMeetingRepository()),
    );
    await tester.pump();

    expect(find.text('회의실'), findsOneWidget);
    expect(find.text('새 회의실'), findsOneWidget);
    expect(find.text('🔴 실시간'), findsOneWidget);
    expect(find.text('📦 배치'), findsOneWidget);
    expect(find.text('실시간 회의실이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the create room sheet on a mobile viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      VoiceDocApp(repository: InMemoryMeetingRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 회의실'));
    await tester.pumpAndSettle();

    expect(find.text('새 회의실 만들기'), findsOneWidget);
    expect(find.text('자동 생성 ID'), findsOneWidget);
    expect(find.text('🔴 실시간 STT'), findsOneWidget);
    expect(find.text('📦 배치 전사'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.text('실시간 회의실이 없습니다.'), findsOneWidget);
  });

  testWidgets('separates realtime and batch rooms', (tester) async {
    final now = DateTime(2026, 6, 15);
    final repository = InMemoryMeetingRepository(
      rooms: [
        MeetingRoom(
          localId: 'local-realtime',
          meetingId: 'MTG-20260615-001',
          title: '실시간 회의',
          meetingType: MeetingType.small,
          status: MeetingStatus.ready,
          createdAt: now,
          updatedAt: now,
        ),
        MeetingRoom(
          localId: 'local-batch',
          meetingId: 'MTG-20260615-002',
          title: '배치 회의',
          meetingType: MeetingType.small,
          workflow: MeetingWorkflow.batch,
          status: MeetingStatus.ready,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    await tester.pumpWidget(VoiceDocApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('실시간 회의'), findsOneWidget);
    expect(find.text('배치 회의'), findsNothing);

    await tester.tap(find.text('📦 배치'));
    await tester.pumpAndSettle();

    expect(find.text('실시간 회의'), findsNothing);
    expect(find.text('배치 회의'), findsOneWidget);
    expect(find.text('배치 시작'), findsOneWidget);
  });

  testWidgets('pins the latest realtime transcript at the top', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
              speaker: 'spk_0',
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
    expect(find.textContaining('참석자 1'), findsOneWidget);
    expect(find.textContaining('spk_0'), findsNothing);

    final partialY = tester.getTopLeft(find.text('현재 말하는 내용')).dy;
    final latestY = tester.getTopLeft(find.textContaining('최근 확정 문장')).dy;
    final olderY = tester.getTopLeft(find.textContaining('이전 확정 문장')).dy;
    expect(tester.takeException(), isNull);
    expect(partialY, lessThan(latestY));
    expect(latestY, lessThan(olderY));
  });

  testWidgets('shows one calendar button for the first dated action item', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 6, 22);
    final repository = InMemoryMeetingRepository(
      rooms: [
        MeetingRoom(
          localId: 'local-actions',
          meetingId: 'MTG-20260622-001',
          title: '액션 아이템 회의',
          meetingType: MeetingType.small,
          status: MeetingStatus.completed,
          createdAt: now,
          updatedAt: now,
          summary: '회의 요약',
          actionItems: const [
            ActionItem(
              owner: 'spk_1',
              task: '회의록 초안 공유',
              dueDate: '다음 주 금요일',
              dueDateResolved: '2026-06-26',
            ),
            ActionItem(task: 'PDF 템플릿 확인'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(VoiceDocApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('액션 아이템 회의'));
    await tester.pumpAndSettle();

    expect(find.text('회의록 초안 공유'), findsOneWidget);
    expect(find.text('PDF 템플릿 확인'), findsOneWidget);
    expect(find.textContaining('참석자 2'), findsOneWidget);
    expect(find.textContaining('spk_1'), findsNothing);
    expect(find.text('일정 추가'), findsOneWidget);
  });
}
