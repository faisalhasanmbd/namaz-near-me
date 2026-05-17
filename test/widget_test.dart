import 'package:flutter_test/flutter_test.dart';

import 'package:namaz_near_me/main.dart';

void main() {
  testWidgets('shows nearby mosque experience', (WidgetTester tester) async {
    await tester.pumpWidget(const NamazNearMeApp());

    expect(find.text('Namaz Near Me'), findsOneWidget);
    expect(find.text('Namaz Times — Moradabad'), findsOneWidget);
    expect(find.text('Finding your location...'), findsOneWidget);
    expect(find.text('Khatm Sehri'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.text('Contributor signup'), findsOneWidget);
    expect(find.text('Maslak / Prayer Method'), findsOneWidget);

  });
}
