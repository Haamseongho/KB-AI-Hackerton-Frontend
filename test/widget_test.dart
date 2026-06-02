import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/features/meetings/data/in_memory_meeting_repository.dart';
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
}
