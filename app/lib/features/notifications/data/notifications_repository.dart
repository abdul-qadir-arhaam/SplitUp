import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? actionState; // OPEN | DONE | EXPIRED
  final String? actionResult; // CONFIRMED | REJECTED
  final Map<String, dynamic>? payload;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    this.actionState,
    this.actionResult,
    this.payload,
    required this.createdAt,
  });

  bool get isOpenActionable => actionState == 'OPEN';

  NotificationModel copyWith({
    bool? isRead,
    String? actionState,
    String? actionResult,
    Map<String, dynamic>? payload,
  }) {
    return NotificationModel(
      id: id,
      type: type,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      actionState: actionState ?? this.actionState,
      actionResult: actionResult ?? this.actionResult,
      payload: payload ?? this.payload,
      createdAt: createdAt,
    );
  }
}

class NotificationsRepository {
  final List<NotificationModel> _items = [
    NotificationModel(
      id: 'notif_settle_sample',
      type: 'SETTLEMENT_REQUESTED',
      title: 'Settlement Requested',
      body: 'Rahul sent ₹850 settlement request for Friday Gang',
      isRead: false,
      actionState: 'OPEN',
      payload: {
        'settlementId': 'stl_sample_rahul',
        'fromUserId': 'usr_rahul',
        'amountPaise': 85000,
        'senderName': 'Rahul',
      },
      createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
    ),
    NotificationModel(
      id: 'notif_1',
      type: 'FRIEND_ADDED',
      title: 'Priya added you as a friend',
      body: 'You can now split shared expenses and settle dues together.',
      isRead: false,
      createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
    ),
    NotificationModel(
      id: 'notif_2',
      type: 'EXPENSE_ADDED',
      title: 'Dinner at Wharf added',
      body: 'Arhaam added an expense of ₹1,200 in Friday Gang.',
      isRead: true,
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
  ];

  Future<List<NotificationModel>> fetchNotifications() async {
    return List.unmodifiable(_items);
  }

  Future<void> addNotification(NotificationModel notif) async {
    _items.insert(0, notif);
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(isRead: true);
    }
  }

  Future<void> markAllRead() async {
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
  }

  Future<void> updateActionState(String id, String actionState, {String? actionResult}) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(
        actionState: actionState,
        actionResult: actionResult,
        isRead: true,
      );
    }
  }

  Future<void> updateSettlementAction(String settlementId, String actionState, {String? actionResult}) async {
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].payload?['settlementId'] == settlementId) {
        _items[i] = _items[i].copyWith(
          actionState: actionState,
          actionResult: actionResult,
          isRead: true,
        );
      }
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository();
});

class NotificationsNotifier extends AsyncNotifier<List<NotificationModel>> {
  @override
  Future<List<NotificationModel>> build() async {
    final repo = ref.read(notificationsRepositoryProvider);
    return repo.fetchNotifications();
  }

  Future<void> addNotification(NotificationModel notif) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.addNotification(notif);
    ref.invalidateSelf();
  }

  Future<void> markRead(String id) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.markRead(id);
    ref.invalidateSelf();
  }

  Future<void> markAllRead() async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.markAllRead();
    ref.invalidateSelf();
  }

  Future<void> updateActionState(String id, String actionState, {String? actionResult}) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.updateActionState(id, actionState, actionResult: actionResult);
    ref.invalidateSelf();
  }

  Future<void> updateSettlementAction(String settlementId, String actionState, {String? actionResult}) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.updateSettlementAction(settlementId, actionState, actionResult: actionResult);
    ref.invalidateSelf();
  }
}

final notificationsNotifierProvider = AsyncNotifierProvider<NotificationsNotifier, List<NotificationModel>>(() {
  return NotificationsNotifier();
});

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final asyncNotifs = ref.watch(notificationsNotifierProvider);
  return asyncNotifs.maybeWhen(
    data: (items) => items.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});
