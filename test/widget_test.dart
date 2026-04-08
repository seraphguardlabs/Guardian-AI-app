import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:guardian_ai_gemma4/main.dart';

void main() {
  testWidgets('Guardian app renders', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const GuardianApp());

    expect(find.textContaining('Guardian AI'), findsOneWidget);
  });
}
