import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:step_circle/app/app.dart';
import 'package:step_circle/features/auth/providers.dart';

void main() {
  testWidgets('shows the Firebase setup gate before configuration', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [firebaseAppProvider.overrideWith((ref) async => null)],
        child: const StepCircleApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Firebase setup required'), findsOneWidget);
  });
}
