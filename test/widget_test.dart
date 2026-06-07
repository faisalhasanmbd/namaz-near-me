import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:namaz_near_me/main.dart';
import 'package:namaz_near_me/providers/app_provider.dart';

void main() {
  testWidgets('app mounts and shows core UI elements', (tester) async {
    // AppState is provided in main() above NamazNearMeApp.
    // Tests must wrap it here to avoid ProviderNotFoundException.
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: const NamazNearMeApp(),
      ),
    );

    // Allow one frame — enough for the scaffold to render without triggering
    // platform channel calls from Geolocator or Firebase.
    await tester.pump();

    expect(find.text('Namaz Near Me'), findsOneWidget);
    expect(find.text('Add / Update Mosque'), findsOneWidget);
  });
}
