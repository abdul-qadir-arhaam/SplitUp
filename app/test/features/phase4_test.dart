import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/groups/data/groups_repository.dart';
import 'package:app/features/groups/presentation/groups_screen.dart';
import 'package:app/features/groups/presentation/create_group_screen.dart';
import 'package:app/features/groups/presentation/group_detail_screen.dart';
import 'package:app/features/groups/presentation/group_settle_graph_screen.dart';
import 'package:app/features/offsets/data/offsets_repository.dart';
import 'package:app/features/friends/data/friends_repository.dart';
import 'package:app/features/friends/presentation/friend_detail_screen.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 4: Groups Repository & Admin Rules', () {
    test('Create group assigns creator as ADMIN', () async {
      final repo = GroupsRepository();
      final group = await repo.createGroup(
        name: 'Goa Squad',
        memberUserIds: ['usr_rahul', 'usr_priya'],
        creatorUserId: 'usr_arhaam',
      );

      expect(group.name, 'Goa Squad');
      expect(group.creatorUserId, 'usr_arhaam');
      expect(group.isAdmin, true);
      expect(group.memberIds, contains('usr_arhaam'));
      expect(group.memberIds, contains('usr_rahul'));
      expect(group.memberIds, contains('usr_priya'));

      final creatorMember = group.members.firstWhere((m) => m.userId == 'usr_arhaam');
      expect(creatorMember.role, 'ADMIN');
    });

    test('Non-admin is blocked from renaming or adding members', () async {
      final repo = GroupsRepository();
      final group = await repo.createGroup(
        name: 'Flat 402',
        memberUserIds: ['usr_rahul'],
        creatorUserId: 'usr_arhaam',
      );

      // Rahul (member, not admin) tries to rename -> Throws Exception
      expect(
        () => repo.updateGroup(group.id, name: 'Rahul Flat', actorUserId: 'usr_rahul'),
        throwsA(isA<Exception>()),
      );

      // Rahul tries to add Priya -> Throws Exception
      expect(
        () => repo.addMember(group.id, 'usr_priya', actorUserId: 'usr_rahul'),
        throwsA(isA<Exception>()),
      );
    });

    test('Unsettled balance prevents member removal or group deletion', () async {
      final repo = GroupsRepository();
      final groups = await repo.fetchGroups();
      final fridayGang = groups.firstWhere((g) => g.name == 'Friday Gang');

      // Arhaam owes money in Friday Gang (-120000 paise)
      expect(fridayGang.myNetPaise, isNegative);

      // Leaving while having unsettled balance must throw
      expect(
        () => repo.removeMember(fridayGang.id, 'usr_arhaam', actorUserId: 'usr_arhaam'),
        throwsA(predicate((e) => e.toString().contains('UNSETTLED_BALANCE'))),
      );

      // Deleting group while members have unsettled balance must throw
      expect(
        () => repo.deleteGroup(fridayGang.id, actorUserId: 'usr_arhaam'),
        throwsA(predicate((e) => e.toString().contains('UNSETTLED_BALANCE'))),
      );
    });

    test('Dashboard aggregates categories, member bars, and spending over time', () {
      final repo = GroupsRepository();
      final dashboard = repo.getDashboard('grp_friday');

      expect(dashboard.categories.isNotEmpty, true);
      expect(dashboard.memberBars.length, greaterThanOrEqualTo(2));
      expect(dashboard.spendingOverTime.isNotEmpty, true);
    });

    test('Graph returns nodes and links for simplified and actual modes', () {
      final repo = GroupsRepository();
      final simplified = repo.getGraph('grp_friday', simplified: true);
      final actual = repo.getGraph('grp_friday', simplified: false);

      expect(simplified.mode, 'simplified');
      expect(simplified.nodes.length, 4);
      expect(simplified.links.length, lessThanOrEqualTo(4));

      expect(actual.mode, 'actual');
      expect(actual.links.length, greaterThan(0));
    });
  });

  group('Phase 4: Offsets Repository (Atomic dual-ledger)', () {
    test('Suggestions offer offset when group debt and individual credit exist', () async {
      final container = ProviderContainer();

      final friendsRepo = container.read(friendsRepositoryProvider);
      final offsetsRepo = container.read(offsetsRepositoryProvider);

      // Ensure Rahul owes Arhaam individually (netPaise > 0)
      friendsRepo.setBalance('usr_rahul', 6000); // Rahul owes Arhaam 6000 paise

      final suggestions = await offsetsRepo.getSuggestions('grp_friday');
      expect(suggestions.isNotEmpty, true);

      final s = suggestions.firstWhere((sug) => sug.toUserId == 'usr_rahul');
      expect(s.toUserId, 'usr_rahul');
      expect(s.maxOffsetPaise, greaterThan(0));

      container.dispose();
    });

    test('Offset confirmation atomically updates both group and individual balances', () async {
      final container = ProviderContainer();

      final friendsRepo = container.read(friendsRepositoryProvider);
      final groupsRepo = container.read(groupsRepositoryProvider);
      final offsetsRepo = container.read(offsetsRepositoryProvider);

      friendsRepo.setBalance('usr_rahul', 50000); // Rahul owes Arhaam 50,000 paise individually

      final offset = await offsetsRepo.createOffset(
        groupLedgerId: 'grp_friday',
        toUserId: 'usr_rahul',
        amountPaise: 50000,
      );
      expect(offset.isPending, true);

      // Confirm offset
      final confirmed = await offsetsRepo.confirmOffset(offset.id);
      expect(confirmed.isConfirmed, true);

      // Check that individual balance with Rahul decreased by 50,000 paise
      final friends = await friendsRepo.fetchFriends();
      final rahul = friends.firstWhere((f) => f.id == 'usr_rahul');
      expect(rahul.netPaise, 0);

      // Check that group balance also improved by 50,000 paise
      final group = await groupsRepo.getGroupById('grp_friday');
      expect(group.myNetPaise, -70000); // Was -120000, now -70000

      container.dispose();
    });
  });

  group('Phase 4 Flutter Widgets', () {
    testWidgets('GroupsScreen displays list of groups with balances', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const GroupsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Friday Gang'), findsOneWidget);
      expect(find.text('Create Group'), findsOneWidget);
    });

    testWidgets('CreateGroupScreen displays member selector and submit button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CreateGroupScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Create Group'), findsWidgets);
      expect(find.text('Arhaam (You)'), findsOneWidget);
      expect(find.text('Group Admin'), findsOneWidget);
    });

    testWidgets('GroupDetailScreen renders Expenses, Dashboard and Settle tabs', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const GroupDetailScreen(groupId: 'grp_friday'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Settle'), findsOneWidget);

      // Switch to Dashboard
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Spending by Category'), findsOneWidget);
      expect(find.text('Member Paid vs. Share'), findsOneWidget);

      // Switch to Settle
      await tester.tap(find.text('Settle'));
      await tester.pumpAndSettle();
      expect(find.text('Settlement Node Graph'), findsOneWidget);
      expect(find.text('Direct Settlement Options'), findsOneWidget);
      // Settle button shown for user's debt
      expect(find.text('Settle'), findsOneWidget);
    });

    testWidgets('GroupSettleGraphScreen displays toggle and payment list', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const GroupSettleGraphScreen(groupId: 'grp_friday'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settlement Graph'), findsOneWidget);
      expect(find.text('Simplified Plan (Min. Steps)'), findsOneWidget);
      expect(find.text('Actual Debts (Pairwise)'), findsOneWidget);
      expect(find.textContaining('Payment List'), findsOneWidget);
    });

    testWidgets('FriendDetailScreen displays "Also in:" chips when shared groups exist', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_rahul'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Also in:'), findsOneWidget);
      expect(find.text('Goa Trip'), findsOneWidget);
      expect(find.text('Friday Gang'), findsOneWidget);
    });
  });
}
