import 'package:flutter_test/flutter_test.dart';

import 'package:schaeflein_lagerview/app.dart';

void main() {
  testWidgets('shows splash then login', (WidgetTester tester) async {
    await tester.pumpWidget(const LagerViewApp());

    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pumpAndSettle();

    expect(find.text('Anmelden'), findsOneWidget);
  });
}
