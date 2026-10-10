import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/features/trips/data/trips_repository.dart';
import 'package:app/features/trips/presentation/trips_screen.dart';
import 'package:app/features/trips/presentation/trip_detail_screen.dart';
import 'package:app/features/groups/data/groups_repository.dart';
import 'package:app/features/groups/presentation/group_detail_screen.dart';
import 'package:app/features/notifications/data/notifications_repository.dart';
import 'package:app/features/expenses/presentation/add_expense_screen.dart';
import 'package:app/core/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 5: Trips Repository & Budget Meter Logic', () {
    test('Scenario 12: Budget meter 4 levels & per-day calculation', () {
      // 1. Under 60% -> UNDER_60 ('On track')
      final meterUnder60 = TripsRepository.computeBudgetMeter(
        5000000, // Rs 50,000
        2500000, // Rs 25,000 (50%)
        '2026-10-12',
        '2026-10-16',
      );
      expect(meterUnder60.spentPercent, 50.0);
      expect(meterUnder60.level, 'UNDER_60');
      expect(meterUnder60.statusMessage, 'On track');
      expect(meterUnder60.isOverBudget, false);

      // 2. Scenario 12: Rs 50,000 budget with Rs 38,400 spent (76.8%) -> 60_TO_80 Amber ('Heads up')
      final meterAmber = TripsRepository.computeBudgetMeter(
        5000000, // Rs 50,000
        3840000, // Rs 38,400 (76.8%)
        '2026-10-12',
        '2026-10-16',
      );
      expect(meterAmber.spentPercent, 76.8);
      expect(meterAmber.level, '60_TO_80');
      expect(meterAmber.statusMessage, 'Heads up');
      expect(meterAmber.remainingPaise, 1160000); // Rs 11,600
      expect(meterAmber.daysTotal, 5); // Oct 12, 13, 14, 15, 16 inclusive
      expect(meterAmber.remainingPerDayPaise, isNotNull);
      expect(meterAmber.isOverBudget, false);

      // 3. 80% to 100% -> 80_TO_100 ('Warning, remaining ₹X')
      final meterWarning = TripsRepository.computeBudgetMeter(
        5000000,
        4200000, // 84%
        '2026-10-12',
        '2026-10-16',
      );
      expect(meterWarning.spentPercent, 84.0);
      expect(meterWarning.level, '80_TO_100');
      expect(meterWarning.statusMessage, contains('Warning, remaining'));
      expect(meterWarning.isOverBudget, false);

      // 4. Over 100% -> OVER_100 ('Over budget by ₹X')
      final meterOver = TripsRepository.computeBudgetMeter(
        5000000,
        5500000, // 110%
        '2026-10-12',
        '2026-10-16',
      );
      expect(meterOver.spentPercent, 110.0);
      expect(meterOver.level, 'OVER_100');
      expect(meterOver.statusMessage, contains('Over budget by'));
      expect(meterOver.isOverBudget, true);
    });

    test('Creating trip copies group members as snapshot (no live link)', () async {
      final repo = TripsRepository();
      final trip = await repo.createTrip(
        name: 'Gokarna Trek',
        budgetPaise: 3000000,
        memberUserIds: ['usr_sneha'],
        sourceGroupId: 'grp_friday',
        creatorUserId: 'usr_arhaam',
      );

      expect(trip.name, 'Gokarna Trek');
      expect(trip.creatorUserId, 'usr_arhaam');
      expect(trip.isAdmin, true);
      // Contains creator + sneha + friday gang members
      expect(trip.members.length, greaterThanOrEqualTo(3));
      final memberUids = trip.members.map((m) => m.userId).toList();
      expect(memberUids, contains('usr_arhaam'));
      expect(memberUids, contains('usr_sneha'));
    });

    test('Creator permissions: only creator can adjust budget and complete trip', () async {
      final repo = TripsRepository();
      final trip = await repo.createTrip(
        name: 'Coorg Weekend',
        budgetPaise: 2500000,
        memberUserIds: ['usr_rahul'],
        creatorUserId: 'usr_arhaam',
      );

      // Non-creator Rahul attempts to change budget -> throws Exception
      expect(
        () => repo.updateTripBudget(trip.id, 4000000, actorUserId: 'usr_rahul'),
        throwsA(isA<Exception>()),
      );

      // Creator Arhaam updates budget -> Success
      final updated = await repo.updateTripBudget(trip.id, 4000000, actorUserId: 'usr_arhaam');
      expect(updated.budgetPaise, 4000000);

      // Non-creator Rahul attempts to complete trip -> throws Exception
      expect(
        () => repo.completeTrip(trip.id, actorUserId: 'usr_rahul'),
        throwsA(isA<Exception>()),
      );

      // Creator Arhaam marks as completed -> Success
      final completed = await repo.completeTrip(trip.id, actorUserId: 'usr_arhaam');
      expect(completed.isCompleted, true);
      expect(completed.status, 'COMPLETED');
    });

    test('Trip isolation: trip graph operates directly without offsets', () {
      final repo = TripsRepository();
      final graph = repo.getGraph('trp_goa_2026');

      expect(graph.nodes.length, 4);
      expect(graph.links.isNotEmpty, true);
      // All links are direct settlements between trip members
      for (final link in graph.links) {
        expect(link.amountPaise, greaterThan(0));
      }
    });
  });

  group('Phase 5: Trips UI Widgets', () {
    testWidgets('TripsScreen displays Active trips and budget bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TripsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Active Trips'), findsOneWidget);
      expect(find.text('Completed Trips'), findsOneWidget);
      expect(find.text('Goa Vacation'), findsOneWidget);
      expect(find.text('Heads up'), findsOneWidget);
    });

    testWidgets('TripDetailScreen renders 4-level budget gauge and tabs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TripDetailScreen(tripId: 'trp_goa_2026'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Goa Vacation'), findsOneWidget);
      expect(find.text('TRIP BUDGET GAUGE'), findsOneWidget);
      expect(find.text('76.8%'), findsOneWidget);
      expect(find.text('Heads up'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Settle'), findsOneWidget);
    });

    testWidgets('TripDetailScreen three-dot menu has View Members and opens members sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: TripDetailScreen(tripId: 'trp_goa_2026'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap three-dot icon
      final moreBtn = find.byIcon(Icons.more_vert_rounded);
      expect(moreBtn, findsOneWidget);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Verify 'View Members' popup option
      expect(find.text('View Members'), findsOneWidget);

      // Tap 'View Members'
      await tester.tap(find.text('View Members'));
      await tester.pumpAndSettle();

      // Verify MembersSheet appears
      expect(find.text('Trip Members'), findsOneWidget);
      expect(find.text('Goa Vacation · 4 members'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Arhaam (You)'), findsOneWidget);
    });

    testWidgets('GroupDetailScreen three-dot menu has View Members and opens members sheet', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: GroupDetailScreen(groupId: 'grp_friday'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap three-dot icon
      final moreBtn = find.byIcon(Icons.more_vert_rounded);
      expect(moreBtn, findsOneWidget);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      // Verify 'View Members' popup option
      expect(find.text('View Members'), findsOneWidget);

      // Tap 'View Members'
      await tester.tap(find.text('View Members'));
      await tester.pumpAndSettle();

      // Verify MembersSheet appears with Add, Remove, and Close buttons on top
      expect(find.text('Group Members'), findsOneWidget);
      expect(find.text('Friday Gang · 5 members'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Arhaam (You)'), findsOneWidget);

      // Verify Remove button on top next to Add and X
      final removeTopBtn = find.widgetWithText(TextButton, 'Remove');
      expect(removeTopBtn, findsOneWidget);

      // Tap Remove on top -> enters remove mode
      await tester.tap(removeTopBtn);
      await tester.pumpAndSettle();

      // Top button changes to 'Done'
      expect(find.widgetWithText(TextButton, 'Done'), findsOneWidget);

      // Tap Remove next to Rahul Sharma (who has an unsettled balance)
      final removeButtons = find.widgetWithText(OutlinedButton, 'Remove');
      expect(removeButtons, findsWidgets);
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      // Verify cannot remove unsettled member alert and automatic notification sent
      expect(find.text('Cannot Remove Member'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Verify SnackBar shown
      expect(find.textContaining('Settlement notification sent to'), findsOneWidget);
    });

    test('Group member removal persists across repository reload (page refresh simulation)', () async {
      final repo1 = GroupsRepository();
      final groups1 = await repo1.fetchGroups();
      final fridayGroup = groups1.firstWhere((g) => g.id == 'grp_friday');

      // Add a settled member (0 balance) so they can be removed
      await repo1.addMember(fridayGroup.id, 'usr_new_member_1');
      final updatedBefore = await repo1.getGroupById(fridayGroup.id);
      expect(updatedBefore.memberIds, contains('usr_new_member_1'));

      // Remove the member
      await repo1.removeMember(fridayGroup.id, 'usr_new_member_1');
      final updatedAfter = await repo1.getGroupById(fridayGroup.id);
      expect(updatedAfter.memberIds.contains('usr_new_member_1'), isFalse);

      // Now create a new repository instance (simulating page reload)
      final repo2 = GroupsRepository();
      final reloadedGroup = await repo2.getGroupById(fridayGroup.id);
      expect(reloadedGroup.memberIds.contains('usr_new_member_1'), isFalse);
    });

    test('Unsettled balance prevents removal (including Amit who owes Priya) and notification is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final groupsRepo = GroupsRepository();
      final notifsRepo = NotificationsRepository();

      // Rahul has unsettled balance in Friday Gang
      expect(
        () => groupsRepo.removeMember('grp_friday', 'usr_rahul'),
        throwsA(predicate((e) => e.toString().contains('UNSETTLED_BALANCE'))),
      );

      // Amit owes Priya and Rahul in Friday Gang -> MUST be blocked
      expect(
        () => groupsRepo.removeMember('grp_friday', 'usr_amit'),
        throwsA(predicate((e) => e.toString().contains('UNSETTLED_BALANCE'))),
      );
      final amitDebt = groupsRepo.checkPendingDebts('usr_amit', groupId: 'grp_friday');
      expect(amitDebt, isNotNull);
      expect(amitDebt, contains('Priya'));

      // Send settlement reminder notification
      final reminder = NotificationModel(
        id: 'notif_test_remind',
        type: 'SETTLEMENT_REQUESTED',
        title: 'Settlement Required: Friday Gang',
        body: 'Amit, you need to settle some payment in Friday Gang with your friends (owes Priya ₹1,500.00).',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await notifsRepo.addNotification(reminder);

      final notifs = await notifsRepo.fetchNotifications();
      expect(notifs.any((n) => n.id == 'notif_test_remind'), isTrue);

      // Verify persistence across repository reload
      final notifsRepo2 = NotificationsRepository();
      final reloadedNotifs = await notifsRepo2.fetchNotifications();
      expect(reloadedNotifs.any((n) => n.id == 'notif_test_remind'), isTrue);
    });

    testWidgets('AddExpenseScreen displays group members when opened with group ledger', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(initialLedgerId: 'grp_friday'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title has group name
      expect(find.text('Add Expense • Friday Gang'), findsOneWidget);
      // Check group members are visible for dividing share
      expect(find.text('You'), findsWidgets);
      expect(find.textContaining('Rahul'), findsWidgets);
      expect(find.textContaining('Priya'), findsWidgets);
      expect(find.textContaining('Amit'), findsWidgets);
    });

    testWidgets('AddExpenseScreen displays trip members when opened with trip ledger', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(initialLedgerId: 'trp_goa_2026'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title has trip name
      expect(find.text('Add Expense • Goa Vacation'), findsOneWidget);
      // Check trip members are visible (Sneha is in Goa trip, but not in Friday group)
      expect(find.text('You'), findsWidgets);
      expect(find.textContaining('Rahul'), findsWidgets);
      expect(find.textContaining('Priya'), findsWidgets);
      expect(find.textContaining('Sneha'), findsWidgets);
    });

    testWidgets('AddExpenseScreen displays selected friends when opened from Home friend picker', (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AddExpenseScreen(
              friendIds: ['usr_sneha', 'usr_priya'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title shows selected friends count
      expect(find.text('Add Expense with 2 friends'), findsOneWidget);
      // Check only You, Sneha, and Priya are participants
      expect(find.text('You'), findsWidgets);
      expect(find.textContaining('Sneha'), findsWidgets);
      expect(find.textContaining('Priya'), findsWidgets);
      // Amit is not among selected friends
      expect(find.textContaining('Amit'), findsNothing);
    });
  });
}
