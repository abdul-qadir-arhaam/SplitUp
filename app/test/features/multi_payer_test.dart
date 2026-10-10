import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/core/widgets/widgets.dart';
import 'package:app/features/expenses/domain/expense_model.dart';
import 'package:app/features/expenses/presentation/add_expense_screen.dart';
import 'package:app/features/expenses/presentation/expense_detail_sheet.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Multiple Payers Feature Tests', () {
    test('Deterministic integer paise leftover distribution', () {
      // Test Rs 1,200 dinner among 3 payers: 120,000 paise ~/ 3 = 40,000 each, 0 leftover
      int totalPaise = 120000;
      List<String> payerIds = ['usr_rahul', 'usr_arhaam', 'usr_amit'];
      final sorted = List<String>.from(payerIds)..sort((a, b) => a.compareTo(b));
      int n = sorted.length;
      int base = totalPaise ~/ n;
      int leftover = totalPaise % n;

      Map<String, int> amounts = {};
      for (int i = 0; i < sorted.length; i++) {
        amounts[sorted[i]] = base + (i < leftover ? 1 : 0);
      }
      expect(amounts['usr_amit'], 40000);
      expect(amounts['usr_arhaam'], 40000);
      expect(amounts['usr_rahul'], 40000);
      expect(amounts.values.fold(0, (a, b) => a + b), 120000);

      // Test Rs 100 with 3 payers: 10,000 paise ~/ 3 = 3333 each, leftover 1 paise
      // Sorted: usr_amit, usr_arhaam, usr_rahul
      // First 1 gets 3334, other 2 get 3333
      totalPaise = 10000;
      base = totalPaise ~/ n;
      leftover = totalPaise % n;
      amounts.clear();
      for (int i = 0; i < sorted.length; i++) {
        amounts[sorted[i]] = base + (i < leftover ? 1 : 0);
      }
      expect(amounts['usr_amit'], 3334);
      expect(amounts['usr_arhaam'], 3333);
      expect(amounts['usr_rahul'], 3333);
      expect(amounts.values.fold(0, (a, b) => a + b), 10000);
    });

    testWidgets('Toggling "Split payers" reveals multi-payer editor and live status', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(
              initialMembers: [
                {'id': 'usr_arhaam', 'name': 'You', 'isMe': true},
                {'id': 'usr_rahul', 'name': 'Rahul', 'isMe': false},
                {'id': 'usr_priya', 'name': 'Priya', 'isMe': false},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check "Split payers" button is visible
      expect(find.text('Split payers'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // Tap "Split payers" to open multi-payer editor
      await tester.tap(find.text('Split payers'));
      await tester.pumpAndSettle();

      // Should now show "Single payer" toggle
      expect(find.text('Single payer'), findsOneWidget);
      // Check live status is visible
      expect(find.textContaining('Paid ₹1,200 of ₹1,200'), findsOneWidget);
      expect(find.text('Matches total'), findsOneWidget);

      // Helper action button is visible
      expect(find.text('Split equally among payers'), findsOneWidget);
    });

    testWidgets('Save button is disabled when payer amounts do not equal total', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(
              initialMembers: [
                {'id': 'usr_arhaam', 'name': 'You', 'isMe': true},
                {'id': 'usr_rahul', 'name': 'Rahul', 'isMe': false},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Split payers"
      await tester.tap(find.text('Split payers'));
      await tester.pumpAndSettle();

      // Find the payer amount input field and change it to 500
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.last, '500');
      await tester.pumpAndSettle();

      // Live status shows left amount
      expect(find.textContaining('left'), findsOneWidget);
      expect(find.textContaining('Payer amounts total'), findsOneWidget);

      // PrimaryButton exists but has null onPressed
      final primaryButton = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(primaryButton.onPressed, isNull);
    });

    testWidgets('"Split equally among payers" divides amount and matches total', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(
              initialMembers: [
                {'id': 'usr_arhaam', 'name': 'You', 'isMe': true},
                {'id': 'usr_rahul', 'name': 'Rahul', 'isMe': false},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Split payers"
      await tester.tap(find.text('Split payers'));
      await tester.pumpAndSettle();

      // Tap "Split equally among payers"
      await tester.tap(find.text('Split equally among payers'));
      await tester.pumpAndSettle();

      // Both should have ₹600 each and match total
      expect(find.text('Matches total'), findsOneWidget);
      expect(find.textContaining('Paid ₹1,200 of ₹1,200'), findsOneWidget);

      // PrimaryButton should be enabled
      final primaryButton = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(primaryButton.onPressed, isNotNull);
    });

    testWidgets('Marking a payer "Not there" removes them from payers and notifies user', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(
              initialMembers: [
                {'id': 'usr_arhaam', 'name': 'You', 'isMe': true},
                {'id': 'usr_rahul', 'name': 'Rahul', 'isMe': false},
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Split payers"
      await tester.tap(find.text('Split payers'));
      await tester.pumpAndSettle();

      // Split equally so Rahul is an active payer
      await tester.tap(find.text('Split equally among payers'));
      await tester.pumpAndSettle();

      // Now toggle Rahul to "Not there" in Split Between section
      final switches = find.byType(Switch);
      expect(switches, findsNWidgets(2));
      // Rahul's switch is the second switch
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();

      // Verify SnackBar notice is displayed
      expect(find.textContaining('Removed Rahul from payers because they are marked "Not there"'), findsOneWidget);
    });

    testWidgets('ExpenseDetailSheet displays all payers and their paid amounts', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final multiPayerExpense = ExpenseModel(
        id: 'exp_test_multi',
        ledgerId: 'grp_friday',
        title: 'Team Dinner',
        totalPaise: 120000,
        category: 'food',
        splitType: 'EQUAL',
        expenseDate: '2026-10-10',
        payers: const [
          ExpensePayer(userId: 'usr_arhaam', paidPaise: 20000),
          ExpensePayer(userId: 'usr_rahul', paidPaise: 60000),
          ExpensePayer(userId: 'usr_amit', paidPaise: 40000),
        ],
        splits: const [
          ExpenseSplit(userId: 'usr_arhaam', owedPaise: 40000, included: true),
          ExpenseSplit(userId: 'usr_rahul', owedPaise: 40000, included: true),
          ExpenseSplit(userId: 'usr_amit', owedPaise: 40000, included: true),
        ],
        createdBy: 'usr_arhaam',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ExpenseDetailSheet(expense: multiPayerExpense),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and all payers are displayed
      expect(find.text('Paid by (3 people)'), findsOneWidget);
      expect(find.text('You'), findsWidgets);
      expect(find.text('₹200'), findsOneWidget);
      expect(find.text('₹600'), findsOneWidget);
      // Amit's payment (₹400) and Your share (₹400) are both ₹400
      expect(find.text('₹400'), findsNWidgets(2));

      // Check Edit button is present
      expect(find.text('Edit'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });
  });
}
