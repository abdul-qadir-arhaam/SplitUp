import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/expense_model.dart';
import '../../friends/data/friends_repository.dart';
import '../../notifications/data/notifications_repository.dart';

class ExpensesRepository {
  final Ref _ref;

  final List<ExpenseModel> _expenses = [
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

  final List<ExpenseActivityItem> _activities = [];

  ExpensesRepository(this._ref);

  Future<List<ExpenseModel>> fetchExpensesForLedger(String ledgerId) async {
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

    // If for a 1-to-1 friend, adjust net balance
    if (friendId != null) {
      final myPaid = payers.where((p) => p.userId == 'usr_arhaam').fold(0, (sum, p) => sum + p.paidPaise);
      final myShare = splits.where((s) => s.userId == 'usr_arhaam' && s.included).fold(0, (sum, s) => sum + s.owedPaise);
      final myNetImpact = myPaid - myShare; // positive if Arhaam is owed money, negative if owes
      _ref.read(friendsRepositoryProvider).adjustBalance(friendId, myNetImpact);
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
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) throw Exception('Expense not found');

    final old = _expenses[index];
    _expenses[index] = old.copyWith(
      deletedAt: DateTime.now(),
      deletedBy: 'usr_arhaam',
    );

    // Revert balance impact
    if (friendId != null) {
      final myPaid = old.payers.where((p) => p.userId == 'usr_arhaam').fold(0, (sum, p) => sum + p.paidPaise);
      final myShare = old.splits.where((s) => s.userId == 'usr_arhaam' && s.included).fold(0, (sum, s) => sum + s.owedPaise);
      final myNetImpact = myPaid - myShare;
      // Reverse it: subtract myNetImpact
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
    final index = _expenses.indexWhere((e) => e.id == expenseId);
    if (index == -1) throw Exception('Expense not found');

    final exp = _expenses[index];
    _expenses[index] = exp.copyWith(isDisputed: true);

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
    return repo._expenses.where((e) => e.deletedAt == null).toList();
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
