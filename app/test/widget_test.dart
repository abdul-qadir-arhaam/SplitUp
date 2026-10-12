import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/app.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('SplitUpApp opens generic login screen for first-time unauthenticated users', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: SplitUpApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify login page elements
    expect(find.text('Log In'), findsWidgets);
    expect(find.textContaining("Don't have an account?"), findsOneWidget);
  });

  testWidgets('SplitUpApp loads home and navigation shell when user is authenticated', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'splitup_auth_token': 'Bearer demo',
      'splitup_user_id': 'usr_arhaam',
      'splitup_user_name': 'Arhaam',
      'splitup_user_phone': '+919876543210',
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: SplitUpApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify main screen elements
    expect(find.text('SplitUp'), findsWidgets);
    expect(find.text('Friends'), findsWidgets);
    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Trips'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });
}
