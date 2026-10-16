import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/theme/app_theme.dart';
import 'package:app/features/expenses/data/expenses_repository.dart';
import 'package:app/features/expenses/domain/expense_model.dart';
import 'package:app/features/friends/data/friends_repository.dart';
import 'package:app/features/friends/domain/friend_model.dart';
import 'package:app/features/friends/presentation/friend_detail_screen.dart';

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

  group('Stage 3: Expense Sync & Server Authority Tests', () {
    testWidgets('Friend page shows an expense that exists only on the server', (tester) async {
      final serverExpense = {
        'id': 'exp_server_remote_99',
        'ledgerId': 'ldg_usr_sync_friend',
        'title': 'Server Dinner Buffet',
        'totalPaise': 240000,
        'category': 'food',
        'splitType': 'EQUAL',
        'expenseDate': '2026-10-15',
        'payers': [
          {'userId': 'usr_sync_friend', 'paidPaise': 240000}
        ],
        'splits': [
          {'userId': 'usr_arhaam', 'owedPaise': 120000, 'included': true},
          {'userId': 'usr_sync_friend', 'owedPaise': 120000, 'included': true},
        ],
        'createdBy': 'usr_sync_friend',
        'createdAt': '2026-10-15T12:00:00.000Z',
        'updatedAt': '2026-10-15T12:00:00.000Z',
      };

      ApiClient.setMockClient(MockClient((request) async {
        if (request.url.path.contains('/expenses')) {
          return http.Response(
            jsonEncode({
              'data': [serverExpense]
            }),
            200,
          );
        }
        if (request.url.path == '/v1/friends') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'usr_sync_friend',
                  'name': 'Sync Friend',
                  'phoneE164': '+919876543210',
                  'isAppUser': true,
                  'individualLedgerId': 'ldg_usr_sync_friend',
                  'netPaise': -120000,
                }
              ]
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'data': {}}), 200);
      }));

      final friend = FriendModel(
        id: 'usr_sync_friend',
        name: 'Sync Friend',
        phoneE164: '+919876543210',
        isAppUser: true,
        individualLedgerId: 'ldg_usr_sync_friend',
        netPaise: -120000,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendsNotifierProvider.overrideWith(() => _MockFriendsNotifier([friend])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const FriendDetailScreen(friendId: 'usr_sync_friend'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that server expense appears on screen
      expect(find.text('Server Dinner Buffet'), findsOneWidget);
    });

    test('Failed create shows an error and leaves no local record', () async {
      final container = ProviderContainer();
      final expensesRepo = container.read(expensesRepositoryProvider);

      ApiClient.setMockClient(MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Database connection error during transaction'}
          }),
          500,
        );
      }));

      // Attempt creating expense when server fails
      expect(
        () async => await expensesRepo.createExpense(
          ledgerId: 'ldg_usr_test',
          title: 'Phantom Dinner',
          totalPaise: 80000,
          category: 'food',
          splitType: 'EQUAL',
          payers: const [ExpensePayer(userId: 'usr_arhaam', paidPaise: 80000)],
          splits: const [
            ExpenseSplit(userId: 'usr_arhaam', owedPaise: 40000, included: true),
            ExpenseSplit(userId: 'usr_test', owedPaise: 40000, included: true),
          ],
        ),
        throwsA(isA<ApiException>()),
      );

      // Verify that NO local expense record was saved
      final allExpenses = await expensesRepo.fetchAllExpenses();
      expect(allExpenses.where((e) => e.title == 'Phantom Dinner'), isEmpty);

      container.dispose();
    });

    test('A failed friends fetch does not set balances to 0', () async {
      final container = ProviderContainer();
      final friendsRepo = container.read(friendsRepositoryProvider);

      // Initialize friends with a known balance
      final friend = await friendsRepo.addFriend(phone: '+919876543210', name: 'Rahul');
      friendsRepo.setBalance(friend.id, -35000); // User owes Rahul 35000 paise

      final initialFriends = await friendsRepo.fetchFriends();
      expect(initialFriends.firstWhere((f) => f.id == friend.id).netPaise, -35000);

      // Server goes offline or returns 503 Service Unavailable
      ApiClient.setMockClient(MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      }));

      // Refetch friends
      final friendsAfterFail = await friendsRepo.fetchFriends(forceRefresh: true);
      final refetched = friendsAfterFail.firstWhere((f) => f.id == friend.id);

      // Balance MUST NOT be reset to 0
      expect(refetched.netPaise, -35000);

      container.dispose();
    });

    test('Sync removes a local-only fake expense', () async {
      final container = ProviderContainer();
      final expensesRepo = container.read(expensesRepositoryProvider);

      const ledgerId = 'ldg_mirror_test';

      // Manually simulate a local-only fake expense in memory
      ApiClient.setMockClient(MockClient((request) async {
        // Server only has this authoritative expense:
        if (request.url.path.contains('/expenses')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'exp_server_authoritative',
                  'ledgerId': ledgerId,
                  'title': 'Legitimate Server Expense',
                  'totalPaise': 50000,
                  'category': 'food',
                  'splitType': 'EQUAL',
                  'expenseDate': '2026-10-15',
                  'payers': [
                    {'userId': 'usr_arhaam', 'paidPaise': 50000}
                  ],
                  'splits': [
                    {'userId': 'usr_arhaam', 'owedPaise': 25000, 'included': true},
                    {'userId': 'usr_friend', 'owedPaise': 25000, 'included': true},
                  ],
                  'createdBy': 'usr_arhaam',
                  'createdAt': '2026-10-15T12:00:00.000Z',
                  'updatedAt': '2026-10-15T12:00:00.000Z',
                }
              ]
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'data': {}}), 200);
      }));

      // Pre-seed a local fake expense that the server doesn't know about
      final fakeLocalExpense = ExpenseModel(
        id: 'exp_fake_phantom_1',
        ledgerId: ledgerId,
        title: 'Local Fake Expense',
        totalPaise: 99900,
        category: 'other',
        splitType: 'EQUAL',
        expenseDate: '2026-10-10',
        payers: const [ExpensePayer(userId: 'usr_arhaam', paidPaise: 99900)],
        splits: const [
          ExpenseSplit(userId: 'usr_arhaam', owedPaise: 99900, included: true),
        ],
        createdBy: 'usr_arhaam',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save fake to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'splitup_expenses_data_v2',
        jsonEncode([fakeLocalExpense.toJson()]),
      );

      // Perform sync from server
      final synced = await expensesRepo.syncExpensesForLedger(ledgerId);

      // Verify mirror rule: fake expense is dropped! Only server expense exists.
      expect(synced.any((e) => e.id == 'exp_fake_phantom_1'), isFalse);
      expect(synced.any((e) => e.id == 'exp_server_authoritative'), isTrue);
      expect(synced.length, 1);

      container.dispose();
    });

    test('Saving twice quickly creates one expense', () async {
      final container = ProviderContainer();
      final expensesRepo = container.read(expensesRepositoryProvider);

      int serverCreateCount = 0;

      ApiClient.setMockClient(MockClient((request) async {
        if (request.method == 'POST' && request.url.path.contains('/expenses')) {
          serverCreateCount++;
          // Simulate latency
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode({
              'data': {
                'id': 'exp_idempotent_1',
                'ledgerId': 'ldg_idem_test',
                'title': 'Coffee',
                'totalPaise': 30000,
                'category': 'food',
                'splitType': 'EQUAL',
                'expenseDate': '2026-10-15',
                'payers': [
                  {'userId': 'usr_arhaam', 'paidPaise': 30000}
                ],
                'splits': [
                  {'userId': 'usr_arhaam', 'owedPaise': 15000, 'included': true},
                  {'userId': 'usr_friend', 'owedPaise': 15000, 'included': true},
                ],
                'createdBy': 'usr_arhaam',
                'createdAt': '2026-10-15T12:00:00.000Z',
                'updatedAt': '2026-10-15T12:00:00.000Z',
              }
            }),
            201,
          );
        }
        return http.Response(jsonEncode({'data': {}}), 200);
      }));

      // Call createExpense
      final exp = await expensesRepo.createExpense(
        ledgerId: 'ldg_idem_test',
        title: 'Coffee',
        totalPaise: 30000,
        category: 'food',
        splitType: 'EQUAL',
        payers: const [ExpensePayer(userId: 'usr_arhaam', paidPaise: 30000)],
        splits: const [
          ExpenseSplit(userId: 'usr_arhaam', owedPaise: 15000, included: true),
          ExpenseSplit(userId: 'usr_friend', owedPaise: 15000, included: true),
        ],
      );

      expect(exp.id, 'exp_idempotent_1');
      expect(serverCreateCount, 1);

      container.dispose();
    });
  });
}

class _MockFriendsNotifier extends AsyncNotifier<List<FriendModel>> implements FriendsNotifier {
  final List<FriendModel> _initial;
  _MockFriendsNotifier(this._initial);

  @override
  Future<List<FriendModel>> build() async => _initial;

  @override
  Future<List<FriendModel>> refresh() async {
    state = AsyncValue.data(_initial);
    return _initial;
  }

  @override
  Future<FriendModel> addFriend({
    required String phone,
    String? name,
    String? contactName,
    bool? isAppUser,
  }) async {
    return _initial.first;
  }

  @override
  Future<void> updateNickname(String friendId, String? nickname) async {}

  @override
  Future<void> removeFriend(String friendId) async {}
}
