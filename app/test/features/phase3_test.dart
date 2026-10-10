import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/friends/data/friends_repository.dart';
import 'package:app/features/friends/domain/friend_model.dart';
import 'package:app/features/friends/presentation/friend_detail_screen.dart';
import 'package:app/features/profile/presentation/profile_screen.dart';
import 'package:app/features/expenses/data/expenses_repository.dart';
import 'package:app/features/expenses/domain/expense_model.dart';
import 'package:app/features/settlements/data/settlements_repository.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Phase 3 Flutter: Settlements and Expenses Repositories', () {
    test('Settlement lifecycle in SettlementsRepository updates friends and notifications', () async {
      final container = ProviderContainer();

      final friendsRepo = container.read(friendsRepositoryProvider);
      final settlementsRepo = container.read(settlementsRepositoryProvider);

      // Add friend with balance owed (Rahul owes Arhaam 120000 paise)
      final friend = await friendsRepo.addFriend(phone: '+919999900010', name: 'Dev Friend');
      friendsRepo.adjustBalance(friend.id, -50000); // Arhaam owes Dev Friend 50000 paise

      // Create settlement
      final settlement = await settlementsRepo.createSettlement(
        ledgerId: friend.individualLedgerId,
        toUserId: friend.id,
        amountPaise: 50000,
        method: 'UPI',
      );

      expect(settlement.status, 'PENDING');

      // Confirm settlement
      final confirmed = await settlementsRepo.confirmSettlement(settlement.id);
      expect(confirmed.status, 'CONFIRMED');

      // Balance with Dev Friend is now 0!
      final friends = await friendsRepo.fetchFriends();
      final updatedFriend = friends.firstWhere((f) => f.id == friend.id);
      expect(updatedFriend.netPaise, 0);

      container.dispose();
    });

    test('Placeholder receiver creates self-confirmed (unverified) settlement immediately', () async {
      final container = ProviderContainer();

      final settlementsRepo = container.read(settlementsRepositoryProvider);

      final settlement = await settlementsRepo.createSettlement(
        ledgerId: 'ldg_placeholder',
        toUserId: 'usr_placeholder',
        amountPaise: 30000,
        isPlaceholderReceiver: true,
      );

      expect(settlement.status, 'CONFIRMED');
      expect(settlement.confirmedOnBehalf, true);

      container.dispose();
    });

    test('Expense create, dispute, and delete lifecycle in ExpensesRepository', () async {
      final container = ProviderContainer();

      final expensesRepo = container.read(expensesRepositoryProvider);
      final friendsRepo = container.read(friendsRepositoryProvider);

      final friend = await friendsRepo.addFriend(phone: '+919999900011', name: 'Kavita');

      // Arhaam pays 100000 paise, split equally with Kavita (Kavita owes Arhaam 50000)
      final expense = await expensesRepo.createExpense(
        ledgerId: friend.individualLedgerId,
        title: 'Team Outing',
        totalPaise: 100000,
        category: 'food',
        splitType: 'EQUAL',
        payers: const [ExpensePayer(userId: 'usr_arhaam', paidPaise: 100000)],
        splits: [
          const ExpenseSplit(userId: 'usr_arhaam', owedPaise: 50000, included: true),
          ExpenseSplit(userId: friend.id, owedPaise: 50000, included: true),
        ],
        friendId: friend.id,
      );

      final friendsAfterExp = await friendsRepo.fetchFriends();
      final updatedFriend = friendsAfterExp.firstWhere((f) => f.id == friend.id);
      expect(updatedFriend.netPaise, 50000); // Kavita owes Arhaam 50000

      // Dispute expense -> does not alter balance
      await expensesRepo.disputeExpense(expense.id);
      final expenses = await expensesRepo.fetchExpensesForLedger(friend.individualLedgerId);
      final disputed = expenses.firstWhere((e) => e.id == expense.id);
      expect(disputed.isDisputed, true);

      // Delete expense -> reverses balance back to 0
      await expensesRepo.deleteExpense(expense.id, friendId: friend.id);
      final friendsAfterDel = await friendsRepo.fetchFriends();
      expect(friendsAfterDel.firstWhere((f) => f.id == friend.id).netPaise, 0);

      container.dispose();
    });
  });

  group('Phase 3 Flutter: UI Invariants and Presentation', () {
    testWidgets('ProfileScreen renders Financial Totals summary card', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: ProfileScreen(
              currentThemeMode: ThemeMode.dark,
              onThemeModeChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('FINANCIAL TOTALS'), findsOneWidget);
      expect(find.text('Total you owe'), findsOneWidget);
      expect(find.text('Total you are owed'), findsOneWidget);
      expect(find.text('Net Balance'), findsOneWidget);
    });

    testWidgets('FriendDetailScreen shows Settle button when user owes money', (tester) async {
      final oweFriend = FriendModel(
        id: 'usr_rahul',
        name: 'Rahul',
        phoneE164: '+919876543210',
        isAppUser: true,
        individualLedgerId: 'ldg_usr_rahul',
        netPaise: -124000, // Arhaam owes Rahul
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsNotifierProvider.overrideWith(() => _MockFriendsNotifier([oweFriend])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_rahul'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Settle button MUST appear because user owes money
      expect(find.textContaining('Settle'), findsWidgets);
    });

    testWidgets('FriendDetailScreen does NOT show Settle button when friend owes user', (tester) async {
      final receiveFriend = FriendModel(
        id: 'usr_priya',
        name: 'Priya',
        phoneE164: '+919876543211',
        isAppUser: true,
        individualLedgerId: 'ldg_usr_priya',
        netPaise: 50000, // Priya owes Arhaam
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsNotifierProvider.overrideWith(() => _MockFriendsNotifier([receiveFriend])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_priya'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Settle button MUST NEVER appear on rows where the user receives money!
      expect(find.textContaining('Settle ₹'), findsNothing);
      expect(find.text('PRIYA OWES YOU'), findsOneWidget);
    });
  });
}

class _MockFriendsNotifier extends FriendsNotifier {
  final List<FriendModel> _mockItems;
  _MockFriendsNotifier(this._mockItems);

  @override
  Future<List<FriendModel>> build() async => _mockItems;
}
