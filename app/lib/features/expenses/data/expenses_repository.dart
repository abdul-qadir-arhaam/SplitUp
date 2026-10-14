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

  Future<List<ExpenseModel>> fetchExpensesForLedger(String ledgerId) async {
    await _ensureLoaded();

    try {
      final res = await ApiClient().get('/v1/ledgers/$ledgerId/expenses');
      if (res != null && res is Map<String, dynamic> && res.containsKey('data')) {
        final list = res['data'] as List<dynamic>;
        final cloudExpenses = list.map((e) => ExpenseModel.fromJson(e as Map<String, dynamic>)).toList();
        for (final ce in cloudExpenses) {
          final idx = _expenses.indexWhere((e) => e.id == ce.id);
          if (idx != -1) {
            _expenses[idx] = ce;
          } else {
            _expenses.add(ce);
          }
        }
        await _saveToStorage();
      }
    } catch (_) {}

    return _expenses
        .where((e) => e.ledgerId == ledgerId && e.deletedAt == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<ExpenseActivityItem>> getActivityForExpense(String expenseId) async {
    return _activities.where((a) => a.payload?['expenseId'] == expenseId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

    // Attempt cloud creation
    try {
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
        _expenses.insert(0, cloudExpense);
        await _saveToStorage();
        return cloudExpense;
      }
    } catch (_) {
      // Offline fallback
    }

    final id = 'exp_${DateTime.now().millisecondsSinceEpoch}';
    final expense = ExpenseModel(
      id: id,
      ledgerId: ledgerId,
      title: title,
      totalPaise: totalPaise,
      category: category,
      splitType: splitType,
      expenseDate: DateTime.now().toIso8601String().split('T')[0],
      note: note,
      payers: payers,
      splits: splits,
      createdBy: 'usr_arhaam',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _expenses.insert(0, expense);
    await _saveToStorage();

    _activities.insert(
      0,
      ExpenseActivityItem(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}',
        action: 'EXPENSE_CREATED',
        actorUserId: 'usr_arhaam',
        createdAt: DateTime.now(),
        payload: {'expenseId': id, 'title': title, 'totalPaise': totalPaise},
      ),
    );

    // If for direct friends (not group or trip ledger), adjust net balance
    if (!ledgerId.startsWith('grp_') && !ledgerId.startsWith('trip_')) {
      final myPaid = payers.where((p) => p.userId == 'usr_arhaam').fold(0, (sum, p) => sum + p.paidPaise);
      final myShare = splits.where((s) => s.userId == 'usr_arhaam' && s.included).fold(0, (sum, s) => sum + s.owedPaise);

      if (friendId != null) {
        final myNetImpact = myPaid - myShare;
        _ref.read(friendsRepositoryProvider).adjustBalance(friendId, myNetImpact);
      } else {
        // Multi-friend expense:
        for (final s in splits) {
          if (s.userId != 'usr_arhaam' && s.included) {
            if (payers.any((p) => p.userId == 'usr_arhaam')) {
              _ref.read(friendsRepositoryProvider).adjustBalance(s.userId, s.owedPaise);
            }
          }
        }
        for (final p in payers) {
          if (p.userId != 'usr_arhaam') {
            _ref.read(friendsRepositoryProvider).adjustBalance(p.userId, -myShare);
          }
        }
      }
      _ref.invalidate(friendsNotifierProvider);
    }

    return expense;
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

    final old = _expenses[index];

    // Revert old balance impact if friendId provided
    if (friendId != null) {
      final oldMyPaid = old.payers.where((p) => p.userId == 'usr_arhaam').fold(0, (sum, p) => sum + p.paidPaise);
      final oldMyShare = old.splits.where((s) => s.userId == 'usr_arhaam' && s.included).fold(0, (sum, s) => sum + s.owedPaise);
      final oldMyNet = oldMyPaid - oldMyShare;

      final newMyPaid = payers.where((p) => p.userId == 'usr_arhaam').fold(0, (sum, p) => sum + p.paidPaise);
      final newMyShare = splits.where((s) => s.userId == 'usr_arhaam' && s.included).fold(0, (sum, s) => sum + s.owedPaise);
      final newMyNet = newMyPaid - newMyShare;

      final diff = newMyNet - oldMyNet;
      _ref.read(friendsRepositoryProvider).adjustBalance(friendId, diff);
      _ref.invalidate(friendsNotifierProvider);
    }

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
    } catch (_) {}

    _activities.insert(
      0,
      ExpenseActivityItem(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}',
        action: 'EXPENSE_EDITED',
        actorUserId: 'usr_arhaam',
        createdAt: DateTime.now(),
        payload: {'expenseId': expenseId, 'title': title, 'totalPaise': totalPaise},
      ),
    );
  }

  Future<void> deleteExpense(String expenseId, {String? friendId}) async {
    await _ensureLoaded();
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) throw Exception('Expense not found');

    final old = _expenses[index];
    _expenses[index] = old.copyWith(
      deletedAt: DateTime.now(),
      deletedBy: 'usr_arhaam',
    );
    await _saveToStorage();

    try {
      await ApiClient().delete('/v1/expenses/$expenseId');
    } catch (_) {}

    // Revert balance impact
    if (friendId != null) {
      final myPaid = old.payers.where((p) => p.userId == 'usr_arhaam').fold(0, (sum, p) => sum + p.paidPaise);
      final myShare = old.splits.where((s) => s.userId == 'usr_arhaam' && s.included).fold(0, (sum, s) => sum + s.owedPaise);
      final myNetImpact = myPaid - myShare;
      _ref.read(friendsRepositoryProvider).adjustBalance(friendId, -myNetImpact);
      _ref.invalidate(friendsNotifierProvider);
    }

    _activities.insert(
      0,
      ExpenseActivityItem(
        id: 'act_${DateTime.now().millisecondsSinceEpoch}',
        action: 'EXPENSE_DELETED',
        actorUserId: 'usr_arhaam',
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
