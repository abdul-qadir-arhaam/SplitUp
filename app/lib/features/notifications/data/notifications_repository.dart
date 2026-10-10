import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
  });

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      type: type,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class NotificationsRepository {
  final List<NotificationModel> _items = [
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
