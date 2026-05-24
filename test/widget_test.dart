import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/main.dart';

void main() {
  testWidgets('shows realtime meeting rooms workflow', (tester) async {
    await tester.pumpWidget(const VoiceDocApp());
    await tester.pump();

    expect(find.text('Meeting Rooms'), findsOneWidget);
    expect(find.text('New Room'), findsOneWidget);
    expect(find.text('REALTIME_TEST'), findsOneWidget);
    expect(find.textContaining('stream PCM audio'), findsOneWidget);
  });
}
