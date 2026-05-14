import 'package:flutter_test/flutter_test.dart';

import 'package:kb_ai_hackerton_frontend/main.dart';

void main() {
  testWidgets('shows meeting upload workflow', (WidgetTester tester) async {
    await tester.pumpWidget(const VoiceDocApp());

    expect(find.text('Voice Doc'), findsOneWidget);
    expect(find.text('회의 음성 업로드'), findsOneWidget);
    expect(find.text('음성 파일 선택 및 업로드'), findsOneWidget);
    expect(find.text('아직 생성된 회의가 없습니다.'), findsOneWidget);
  });
}
