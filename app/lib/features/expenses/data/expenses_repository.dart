import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/expense_model.dart';
import '../../friends/data/friends_repository.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../../core/network/api_client.dart';

class ExpensesRepository {
  static const _storageKey = 'splitup_expenses_data_v2';
  final Ref _ref;
  List<ExpenseModel> _expenses = [];
  final List<ExpenseActivityItem> _activities = [];
  bool _isLoaded = false;

  ExpensesRepository(this._ref) {
    _initDefaultExpenses();
  }

  void _initDefaultExpenses() {
    _expenses = [
      ExpenseModel(
        id: 'exp_1',
        ledgerId: 'ldg_usr_rahul',
        title: 'Dinner at Wharf',
        totalPaise: 120000,
        category: 'food',
        splitType: 'EQUAL',
        expenseDate: '2026-10-10',
        payers: const [ExpensePayer(userId: 'usr_rahul', paidPaise: 120000)],
        splits: const [
          ExpenseSplit(userId: 'usr_rahul', owedPaise: 60000, included: true),
          ExpenseSplit(userId: 'usr_arhaam', owedPaise: 60000, included: true),
        ],
        createdBy: 'usr_rahul',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      ExpenseModel(
        id: 'exp_2',
        ledgerId: 'ldg_usr_priya',
        title: 'Coffee & Snacks',
        totalPaise: 50000,
        category: 'food',
        splitType: 'EQUAL',
        expenseDate: '2026-10-09',
        payers: const [ExpensePayer(userId: 'usr_arhaam', paidPaise: 50000)],
        splits: const [
          ExpenseSplit(userId: 'usr_arhaam', owedPaise: 25000, included: true),
          ExpenseSplit(userId: 'usr_priya', owedPaise: 25000, included: true),
        ],
        createdBy: 'usr_arhaam',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ];
  }

  Future<String> _getStorageKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      if (currentUserId != null && currentUserId != 'usr_arhaam') {
        return 'splitup_expenses_$currentUserId';
      }
    } catch (_) {}
    return _storageKey;
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      final isDemoUser = currentUserId == 'usr_arhaam';
      final isRealNewUser = currentUserId != null && currentUserId != 'usr_arhaam';
      final key = await _getStorageKey();

      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _expenses = decoded.map((e) => ExpenseModel.fromJson(e as Map<String, dynamic>)).toList();
      } else {
        if (isRealNewUser) {
          _expenses = [];
          await _saveToStorage();
        } else if (isDemoUser) {
          _initDefaultExpenses();
        }
      }
    } catch (_) {}
    _isLoaded = true;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();
      final raw = jsonEncode(_expenses.map((e) => e.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (_) {}
  }

  Future<List<ExpenseModel>> fetchAllExpenses() async {
    await _ensureLoaded();
    return _expenses.where((e) => e.deletedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Authoritative server-first sync: calls GET /v1/ledgers/:id/expenses
  /// and makes the local list for that ledger an exact mirror of the server's list.
  /// Drops local-only / phantom expenses that the server does not have.
  Future<List<ExpenseModel>> syncExpensesForLedger(String ledgerId) async {
    await _ensureLoaded();

    try {
      final res = await ApiClient().get('/v1/ledgers/$ledgerId/expenses');
      if (res != null && res is Map<String, dynamic> && res.containsKey('data')) {
        final list = res['data'] as List<dynamic>;
        final cloudExpenses = list.map((e) => ExpenseModel.fromJson(e as Map<String, dynamic>)).toList();
        final cloudIds = cloudExpenses.map((e) => e.id).toSet();

        // Count and log dropped local phantom expenses
        final dropped = _expenses.where((e) => e.ledgerId == ledgerId && !cloudIds.contains(e.id)).toList();
        if (dropped.isNotEmpty) {
          // Clean hygiene: local-only expenses not on the server are removed by the mirror rule
          // ignore: avoid_print
          print('[ExpensesRepository] Dropped ${dropped.length} local-only fake expense(s) for ledger $ledgerId: ${dropped.map((d) => d.id).toList()}');
        }

        // Mirror rule: keep other ledgers' expenses, mirror this ledger exactly from server
        _expenses.removeWhere((e) => e.ledgerId == ledgerId);
        _expenses.addAll(cloudExpenses);
        await _saveToStorage();

        // Invalidate friends provider so screen gets fresh server balances
        try {
          await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
          _ref.invalidate(friendsNotifierProvider);
        } catch (_) {}
      }
    } catch (_) {
      // On network failure retain local cache without wiping balances to zero
    }

    return _expenses
        .where((e) => e.ledgerId == ledgerId && e.deletedAt == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<ExpenseModel>> fetchExpensesForLedger(String ledgerId) async {
    return syncExpensesForLedger(ledgerId);
  }

  Future<List<ExpenseActivityItem>> getActivityForExpense(String expenseId) async {
    return _activities.where((a) => a.payload?['expenseId'] == expenseId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<String> _getCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      if (currentUserId != null && currentUserId.isNotEmpty) {
        return currentUserId;
      }
    } catch (_) {}
    return 'usr_arhaam';
  }

  Future<ExpenseModel> createExpense({
    required String ledgerId,
    required String title,
    required int totalPaise,
    required String category,
    required String splitType,
    required List<ExpensePayer> payers,
    required List<ExpenseSplit> splits,
    String? note,
    String? friendId,
  }) async {
    await _ensureLoaded();
    final currentUserId = await _getCurrentUserId();

    // Authoritative cloud creation: do not catch silently or fall back to fake local expenses
    final res = await ApiClient().post('/v1/ledgers/$ledgerId/expenses', {
      'title': title,
      'totalPaise': totalPaise,
      'category': category.toLowerCase(),
      'splitType': splitType,
      'payers': payers.map((p) => {'userId': p.userId, 'paidPaise': p.paidPaise}).toList(),
      'participants': splits.map((s) => {
        'userId': s.userId,
        'included': s.included,
        'splitValue': s.owedPaise,
      }).toList(),
      'note': note,
    });

    if (res != null && res is Map<String, dynamic> && res.containsKey('data')) {
      final cloudExpense = ExpenseModel.fromJson(res['data'] as Map<String, dynamic>);
      
      final existingIdx = _expenses.indexWhere((e) => e.id == cloudExpense.id);
      if (existingIdx != -1) {
        _expenses[existingIdx] = cloudExpense;
      } else {
        _expenses.insert(0, cloudExpense);
      }
      await _saveToStorage();

      _activities.insert(
        0,
        ExpenseActivityItem(
          id: 'act_${DateTime.now().millisecondsSinceEpoch}',
          action: 'EXPENSE_CREATED',
          actorUserId: currentUserId,
          createdAt: DateTime.now(),
          payload: {'expenseId': cloudExpense.id, 'title': title, 'totalPaise': totalPaise},
        ),
      );

      // Server is the sole authority for balances. Refetch friends from server:
      try {
        await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
        _ref.invalidate(friendsNotifierProvider);
      } catch (_) {}

      return cloudExpense;
    }

    throw const ApiException('Server did not return created expense data. Please try again.');
  }

  Future<void> editExpense(
    String expenseId, {
    required String title,
    required int totalPaise,
    required String category,
    required String splitType,
    required List<ExpensePayer> payers,
    required List<ExpenseSplit> splits,
    String? friendId,
  }) async {
    await _ensureLoaded();
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) throw Exception('Expense not found');

    final currentUserId = await _getCurrentUserId();

    await ApiClient().patch('/v1/expenses/$expenseId', {
      'title': title,
      'totalPaise': totalPaise,
      'category': category.toLowerCase(),
      'splitType': splitType,
      'payers': payers.map((p) => {'userId': p.userId, 'paidPaise': p.paidPaise}).toList(),
      'participants': splits.map((s) => {
        'userId': s.userId,
        'included': s.included,
        'splitValue': s.owedPaise,
      }).toList(),
    });

    final old = _expenses[index];
    _expenses[index] = old.copyWith(
      title: title,
      totalPaise: totalPaise,
      category: category,
      splitType: splitType,
      payers: payers,
      splits: splits,
    );
    await _saveToStorage();

    try {
      await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
      _ref.invalidate(friendsNotifierProvider);
    } catch (_) {}

    _activities.insert(
      0,
      ExpenseActivityItem(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}',
        action: 'EXPENSE_EDITED',
        actorUserId: currentUserId,
        createdAt: DateTime.now(),
        payload: {'expenseId': expenseId, 'title': title, 'totalPaise': totalPaise},
      ),
    );
  }

  Future<void> deleteExpense(String expenseId, {String? friendId}) async {
    await _ensureLoaded();
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) throw Exception('Expense not found');

    final currentUserId = await _getCurrentUserId();

    await ApiClient().delete('/v1/expenses/$expenseId');

    final old = _expenses[index];
    _expenses[index] = old.copyWith(
      deletedAt: DateTime.now(),
      deletedBy: currentUserId,
    );
    await _saveToStorage();

    try {
      await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
      _ref.invalidate(friendsNotifierProvider);
    } catch (_) {}

    _activities.insert(
      0,
      ExpenseActivityItem(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}',
        action: 'EXPENSE_DELETED',
        actorUserId: currentUserId,
        createdAt: DateTime.now(),
        payload: {'expenseId': expenseId, 'title': old.title},
      ),
    );
  }

  Future<void> disputeExpense(String expenseId) async {
    await _ensureLoaded();
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) throw Exception('Expense not found');

    final exp = _expenses[index];
    _expenses[index] = exp.copyWith(isDisputed: true);
    await _saveToStorage();

    _activities.insert(
      0,
      ExpenseActivityItem(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}',
        action: 'EXPENSE_DISPUTED',
        actorUserId: 'usr_arhaam',
        createdAt: DateTime.now(),
        payload: {'expenseId': expenseId, 'title': exp.title},
      ),
    );

    // Notify creator
    if (exp.createdBy != 'usr_arhaam') {
      _ref.read(notificationsRepositoryProvider).addNotification(
            NotificationModel(
              id: 'notif_dsp_${DateTime.now().millisecondsSinceEpoch}',
              type: 'EXPENSE_DISPUTED',
              title: 'Expense Disputed',
              body: 'Arhaam disputed the expense "${exp.title}".',
              isRead: false,
              payload: {'expenseId': expenseId, 'title': exp.title},
              createdAt: DateTime.now(),
            ),
          );
      _ref.invalidate(notificationsNotifierProvider);
    }
  }

  Future<void> clearCache() async {
    _expenses.clear();
    _activities.clear();
    _isLoaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();
      await prefs.remove(key);
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref);
});

class ExpensesNotifier extends AsyncNotifier<List<ExpenseModel>> {
  @override
  Future<List<ExpenseModel>> build() async {
    final repo = ref.read(expensesRepositoryProvider);
    return repo.fetchAllExpenses();
  }

  Future<void> syncExpensesForLedger(String ledgerId) async {
    final repo = ref.read(expensesRepositoryProvider);
    await repo.syncExpensesForLedger(ledgerId);
    ref.invalidateSelf();
  }

  Future<void> createExpense({
    required String ledgerId,
    required String title,
    required int totalPaise,
    required String category,
    required String splitType,
    required List<ExpensePayer> payers,
    required List<ExpenseSplit> splits,
    String? note,
    String? friendId,
  }) async {
    final repo = ref.read(expensesRepositoryProvider);
    await repo.createExpense(
      ledgerId: ledgerId,
      title: title,
      totalPaise: totalPaise,
      category: category,
      splitType: splitType,
      payers: payers,
      splits: splits,
      note: note,
      friendId: friendId,
    );
    ref.invalidateSelf();
  }

  Future<void> editExpense(
    String expenseId, {
    required String title,
    required int totalPaise,
    required String category,
    required String splitType,
    required List<ExpensePayer> payers,
    required List<ExpenseSplit> splits,
    String? friendId,
  }) async {
    final repo = ref.read(expensesRepositoryProvider);
    await repo.editExpense(
      expenseId,
      title: title,
      totalPaise: totalPaise,
      category: category,
      splitType: splitType,
      payers: payers,
      splits: splits,
      friendId: friendId,
    );
    ref.invalidateSelf();
  }

  Future<void> deleteExpense(String expenseId, {String? friendId}) async {
    final repo = ref.read(expensesRepositoryProvider);
    await repo.deleteExpense(expenseId, friendId: friendId);
    ref.invalidateSelf();
  }

  Future<void> disputeExpense(String expenseId) async {
    final repo = ref.read(expensesRepositoryProvider);
    await repo.disputeExpense(expenseId);
    ref.invalidateSelf();
  }
}

final expensesNotifierProvider = AsyncNotifierProvider<ExpensesNotifier, List<ExpenseModel>>(() {
  return ExpensesNotifier();
});
