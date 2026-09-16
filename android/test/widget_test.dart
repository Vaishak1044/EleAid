import 'package:flutter_test/flutter_test.dart';

import 'package:eleaid_companion/main.dart';

void main() {
  testWidgets('EleAid standalone app starts', (WidgetTester tester) async {
    await tester.pumpWidget(const EleAidApp());
    expect(find.text('EleAid Independent Detector'), findsOneWidget);
    expect(find.textContaining('No inference API URL or API key'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });
}
