import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/friends/data/friends_repository.dart';
import 'package:app/features/friends/domain/friend_model.dart';
import 'package:app/features/friends/presentation/friend_detail_screen.dart';
import 'package:app/features/settlements/data/settlements_repository.dart';
import 'package:app/features/settlements/domain/settlement_model.dart';
import 'package:app/features/notifications/data/notifications_repository.dart';
import 'package:app/features/notifications/presentation/notifications_screen.dart';

class _FakeFriendsNotifier extends FriendsNotifier {
  final List<FriendModel> _initialFriends;
  _FakeFriendsNotifier(this._initialFriends);

  @override
  Future<List<FriendModel>> build() async => _initialFriends;

  @override
  Future<List<FriendModel>> refresh() async => _initialFriends;
}

class _FakeSettlementsNotifier extends SettlementsNotifier {
  final List<SettlementModel> _items;
  _FakeSettlementsNotifier(this._items);

  @override
  Future<List<SettlementModel>> build() async => _items;

  @override
  Future<SettlementModel> confirmSettlement(String settlementId) async {
    final idx = _items.indexWhere((s) => s.id == settlementId);
    if (idx != -1) {
      final updated = _items[idx].copyWith(status: 'CONFIRMED');
      _items[idx] = updated;
      state = AsyncValue.data(List.unmodifiable(_items));
      return updated;
    }
    throw Exception('Not found');
  }

  @override
  Future<SettlementModel> cancelSettlement(String settlementId) async {
    final idx = _items.indexWhere((s) => s.id == settlementId);
    if (idx != -1) {
      final updated = _items[idx].copyWith(status: 'CANCELLED');
      _items[idx] = updated;
      state = AsyncValue.data(List.unmodifiable(_items));
      return updated;
    }
    throw Exception('Not found');
  }

  @override
  Future<SettlementModel> rejectSettlement(String settlementId) async {
    final idx = _items.indexWhere((s) => s.id == settlementId);
    if (idx != -1) {
      final updated = _items[idx].copyWith(status: 'REJECTED');
      _items[idx] = updated;
      state = AsyncValue.data(List.unmodifiable(_items));
      return updated;
    }
    throw Exception('Not found');
  }
}

class _FakeNotificationsNotifier extends NotificationsNotifier {
  final List<NotificationModel> _notifs;
  _FakeNotificationsNotifier(this._notifs);

  @override
  Future<List<NotificationModel>> build() async => _notifs;

  @override
  Future<void> updateActionState(String id, String actionState, {String? actionResult}) async {
    final idx = _notifs.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final updated = _notifs[idx].copyWith(actionState: actionState, actionResult: actionResult);
      _notifs[idx] = updated;
      state = AsyncValue.data(List.unmodifiable(_notifs));
    }
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.setMockClient(null);
  });

  tearDown(() {
    ApiClient.setMockClient(null);
  });

  group('Stage 2: Flutter App Settlements & Notifications (Rules R1-R9)', () {
    testWidgets('R7: Zero-balance ledger shows "ALL SETTLED UP" and hides pending settlement banner', (tester) async {
      final friendZero = FriendModel(
        id: 'usr_friend_zero',
        name: 'Zero Balance Friend',
        phoneE164: '+919876543211',
        isAppUser: true,
        individualLedgerId: 'ldg_friend_zero',
        netPaise: 0, // Zero balance!
      );

      final settlement = SettlementModel(
        id: 'stl_test_pending_01',
        ledgerId: 'ldg_friend_zero',
        fromUserId: 'usr_me',
        toUserId: 'usr_friend_zero',
        amountPaise: 50000,
        status: 'PENDING',
        createdBy: 'usr_me',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsNotifierProvider.overrideWith(() => _FakeFriendsNotifier([friendZero])),
            settlementsNotifierProvider.overrideWith(() => _FakeSettlementsNotifier([settlement])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_friend_zero'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Rule R7 verification:
      expect(find.text('ALL SETTLED UP'), findsOneWidget);
      // Banner must NOT be displayed because net balance is 0!
      expect(find.text('Settlement Pending'), findsNothing);
      expect(find.text('Waiting for Zero Balance Friend to confirm receipt.'), findsNothing);
    });

    testWidgets('R5 & R7: Sender view shows Pending banner with Cancel button', (tester) async {
      final friendOwed = FriendModel(
        id: 'usr_friend_owed',
        name: 'Sender Friend',
        phoneE164: '+919876543212',
        isAppUser: true,
        individualLedgerId: 'ldg_friend_owed',
        netPaise: -50000, // I owe 50000 paise
      );

      final settlement = SettlementModel(
        id: 'stl_test_pending_sender',
        ledgerId: 'ldg_friend_owed',
        fromUserId: 'usr_me',
        toUserId: 'usr_friend_owed',
        amountPaise: 50000,
        status: 'PENDING',
        createdBy: 'usr_me',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsNotifierProvider.overrideWith(() => _FakeFriendsNotifier([friendOwed])),
            settlementsNotifierProvider.overrideWith(() => _FakeSettlementsNotifier([settlement])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_friend_owed'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settlement Pending'), findsOneWidget);
      expect(find.text('Waiting for Sender Friend to confirm receipt.'), findsOneWidget);
      expect(find.text('Cancel Request'), findsOneWidget);
    });

    testWidgets('R5: Receiver view shows Confirm and Reject buttons', (tester) async {
      final friendWhoOwes = FriendModel(
        id: 'usr_friend_debtor',
        name: 'Debtor Friend',
        phoneE164: '+919876543213',
        isAppUser: true,
        individualLedgerId: 'ldg_friend_debtor',
        netPaise: 50000, // Debtor owes me 50000 paise
      );

      final settlement = SettlementModel(
        id: 'stl_test_receiver_action',
        ledgerId: 'ldg_friend_debtor',
        fromUserId: 'usr_friend_debtor', // Friend sent to me
        toUserId: 'usr_me',
        amountPaise: 50000,
        status: 'PENDING',
        createdBy: 'usr_friend_debtor',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsNotifierProvider.overrideWith(() => _FakeFriendsNotifier([friendWhoOwes])),
            settlementsNotifierProvider.overrideWith(() => _FakeSettlementsNotifier([settlement])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_friend_debtor'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settlement Pending'), findsOneWidget);
      expect(find.text('Debtor Friend sent you this settlement request.'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets('R8: Notifications screen shows inline Confirm and updates state to DONE', (tester) async {
      final notif = NotificationModel(
        id: 'notif_settle_01',
        type: 'SETTLEMENT_REQUESTED',
        title: 'Settlement Request',
        body: 'Debtor Friend wants to record a ₹500 payment',
        isRead: false,
        createdAt: DateTime.now(),
        actionState: 'OPEN',
        payload: {
          'settlementId': 'stl_test_receiver_action',
          'amountPaise': 50000,
        },
      );

      final settlement = SettlementModel(
        id: 'stl_test_receiver_action',
        ledgerId: 'ldg_test',
        fromUserId: 'usr_friend_debtor',
        toUserId: 'usr_me',
        amountPaise: 50000,
        status: 'PENDING',
        createdBy: 'usr_friend_debtor',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsNotifierProvider.overrideWith(() => _FakeNotificationsNotifier([notif])),
            settlementsNotifierProvider.overrideWith(() => _FakeSettlementsNotifier([settlement])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const NotificationsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      // Tap Confirm
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Rule R8: stays in list with result
      expect(find.text('You confirmed this settlement'), findsOneWidget);
    });
  });
}
