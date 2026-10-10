import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/theme/colors.dart';
import 'package:app/core/widgets/widgets.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Theme and Shared Widgets tests', () {
    test('AppTheme creates valid dark and light themes with SplitUpColors', () {
      final darkTheme = AppTheme.dark();
      final lightTheme = AppTheme.light();

      expect(darkTheme.brightness, Brightness.dark);
      expect(lightTheme.brightness, Brightness.light);

      final darkColors = darkTheme.extension<SplitUpColors>();
      final lightColors = lightTheme.extension<SplitUpColors>();

      expect(darkColors, isNotNull);
      expect(lightColors, isNotNull);
      expect(darkColors!.bgBase, const Color(0xFF0A1411));
      expect(lightColors!.bgBase, const Color(0xFFF5F2EA));
    });

    testWidgets('GlassCard and MoneyText render in both dark and light modes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AppBackground(
              child: GlassCard(
                child: MoneyText(12000000),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('₹1,20,000'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: AppBackground(
              child: GlassCard(
                child: MoneyText(-45000),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('-₹450'), findsOneWidget);
    });

    testWidgets('SettleButton renders formatted amount', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SettleButton(
              amountPaise: 125000,
              onPressed: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Settle ₹1,250'), findsOneWidget);
    });
  });
}
