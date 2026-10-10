import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/app.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('SplitUpApp loads home and navigation shell properly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SplitUpApp(),
      ),
    );

    // Initial settle
    await tester.pumpAndSettle();

    // Verify main screen elements
    expect(find.text('SplitUp'), findsWidgets);
    expect(find.text('Friends'), findsWidgets);
    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Trips'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });
}
