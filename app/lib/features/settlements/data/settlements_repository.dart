import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/settlement_model.dart';
import '../../friends/data/friends_repository.dart';
import '../../notifications/data/notifications_repository.dart';

class SettlementsRepository {
  final Ref _ref;
  final List<SettlementModel> _settlements = [
    SettlementModel(
      id: 'stl_sample_rahul',
      ledgerId: 'ldg_usr_rahul',
      fromUserId: 'usr_rahul',
      toUserId: 'usr_arhaam',
      amountPaise: 85000,
      method: 'UPI',
      status: 'PENDING',
      createdBy: 'usr_rahul',
      createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
  ];

  SettlementsRepository(this._ref);

  Future<List<SettlementModel>> fetchSettlementsForLedger(String ledgerId) async {
    return _settlements.where((s) => s.ledgerId == ledgerId).toList();
  }

  Future<SettlementModel?> getSettlementById(String id) async {
    final matches = _settlements.where((s) => s.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<SettlementModel> createSettlement({
    required String ledgerId,
    required String toUserId,
    required int amountPaise,
    String method = 'CASH',
    bool isPlaceholderReceiver = false,
  }) async {
    final id = 'stl_${DateTime.now().millisecondsSinceEpoch}';
    final isConfirmed = isPlaceholderReceiver;

    final settlement = SettlementModel(
      id: id,
      ledgerId: ledgerId,
      fromUserId: 'usr_arhaam',
      toUserId: toUserId,
      amountPaise: amountPaise,
      method: method,
      status: isConfirmed ? 'CONFIRMED' : 'PENDING',
      confirmedOnBehalf: isConfirmed,
      createdBy: 'usr_arhaam',
      respondedBy: isConfirmed ? 'usr_arhaam' : null,
      createdAt: DateTime.now(),
      respondedAt: isConfirmed ? DateTime.now() : null,
    );

    _settlements.insert(0, settlement);

    if (isConfirmed) {
      // Self-confirmed for placeholder: update friend balance
      _ref.read(friendsRepositoryProvider).applySettlement(toUserId, amountPaise);
      _ref.invalidate(friendsNotifierProvider);
    } else {
      // Pending: emit notification
      _ref.read(notificationsRepositoryProvider).addNotification(
            NotificationModel(
              id: 'notif_$id',
              type: 'SETTLEMENT_REQUESTED',
              title: 'Settlement Created',
              body: 'You requested ₹${(amountPaise / 100).toStringAsFixed(2)} settlement via $method.',
              isRead: true,
              actionState: 'OPEN',
              payload: {
                'settlementId': id,
                'ledgerId': ledgerId,
                'amountPaise': amountPaise,
                'toUserId': toUserId,
              },
              createdAt: DateTime.now(),
            ),
          );
      _ref.invalidate(notificationsNotifierProvider);
    }

    return settlement;
  }

  Future<SettlementModel> confirmSettlement(String settlementId) async {
    final index = _settlements.indexWhere((s) => s.id == settlementId);
    if (index == -1) {
      throw Exception('Settlement not found');
    }

    final old = _settlements[index];
    final updated = old.copyWith(
      status: 'CONFIRMED',
      respondedBy: 'usr_arhaam',
      respondedAt: DateTime.now(),
    );
    _settlements[index] = updated;

    // Apply to friend balance
    final friendId = old.fromUserId == 'usr_arhaam' ? old.toUserId : old.fromUserId;
    _ref.read(friendsRepositoryProvider).applySettlement(friendId, old.amountPaise);
    _ref.invalidate(friendsNotifierProvider);

    // Update notification
    _ref.read(notificationsRepositoryProvider).updateSettlementAction(
          settlementId,
          'DONE',
          actionResult: 'CONFIRMED',
        );
    _ref.invalidate(notificationsNotifierProvider);

    return updated;
  }

  Future<SettlementModel> rejectSettlement(String settlementId) async {
    final index = _settlements.indexWhere((s) => s.id == settlementId);
    if (index == -1) {
      throw Exception('Settlement not found');
    }

    final old = _settlements[index];
    final updated = old.copyWith(
      status: 'REJECTED',
      respondedBy: 'usr_arhaam',
      respondedAt: DateTime.now(),
    );
    _settlements[index] = updated;

    _ref.read(notificationsRepositoryProvider).updateSettlementAction(
          settlementId,
          'DONE',
          actionResult: 'REJECTED',
        );
    _ref.invalidate(notificationsNotifierProvider);

    return updated;
  }

  Future<SettlementModel> cancelSettlement(String settlementId) async {
    final index = _settlements.indexWhere((s) => s.id == settlementId);
    if (index == -1) {
      throw Exception('Settlement not found');
    }

    final old = _settlements[index];
    final updated = old.copyWith(
      status: 'CANCELLED',
      respondedAt: DateTime.now(),
    );
    _settlements[index] = updated;

    _ref.read(notificationsRepositoryProvider).updateSettlementAction(
          settlementId,
          'EXPIRED',
        );
    _ref.invalidate(notificationsNotifierProvider);

    return updated;
  }

  Future<SettlementModel> resubmitSettlement(String settlementId, {int? newAmountPaise}) async {
    final index = _settlements.indexWhere((s) => s.id == settlementId);
    if (index == -1) {
      throw Exception('Settlement not found');
    }

    final old = _settlements[index];
    final amount = newAmountPaise ?? old.amountPaise;

    final newSettlement = await createSettlement(
      ledgerId: old.ledgerId,
      toUserId: old.toUserId,
      amountPaise: amount,
      method: old.method,
    );

    _settlements[index] = old.copyWith(replacedById: newSettlement.id);
    return newSettlement;
  }
}

final settlementsRepositoryProvider = Provider<SettlementsRepository>((ref) {
  return SettlementsRepository(ref);
});

class SettlementsNotifier extends AsyncNotifier<List<SettlementModel>> {
  @override
  Future<List<SettlementModel>> build() async {
    final repo = ref.read(settlementsRepositoryProvider);
    return repo._settlements;
  }

  Future<SettlementModel> createSettlement({
    required String ledgerId,
    required String toUserId,
    required int amountPaise,
    String method = 'CASH',
    bool isPlaceholderReceiver = false,
  }) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.createSettlement(
      ledgerId: ledgerId,
      toUserId: toUserId,
      amountPaise: amountPaise,
      method: method,
      isPlaceholderReceiver: isPlaceholderReceiver,
    );
    ref.invalidateSelf();
    return item;
  }

  Future<void> confirmSettlement(String id) async {
    final repo = ref.read(settlementsRepositoryProvider);
    await repo.confirmSettlement(id);
    ref.invalidateSelf();
  }

  Future<void> rejectSettlement(String id) async {
    final repo = ref.read(settlementsRepositoryProvider);
    await repo.rejectSettlement(id);
    ref.invalidateSelf();
  }

  Future<void> cancelSettlement(String id) async {
    final repo = ref.read(settlementsRepositoryProvider);
    await repo.cancelSettlement(id);
    ref.invalidateSelf();
  }

  Future<SettlementModel> resubmitSettlement(String id, {int? newAmountPaise}) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.resubmitSettlement(id, newAmountPaise: newAmountPaise);
    ref.invalidateSelf();
    return item;
  }
}

final settlementsNotifierProvider = AsyncNotifierProvider<SettlementsNotifier, List<SettlementModel>>(() {
  return SettlementsNotifier();
});
