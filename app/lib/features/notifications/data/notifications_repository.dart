import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';

class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? actionState;
  final String? actionResult;
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

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? 'GENERAL').toString();
    final payload = json['payload'] is Map ? (json['payload'] as Map<String, dynamic>) : <String, dynamic>{};

    String title = json['title']?.toString() ?? '';
    String body = json['body']?.toString() ?? '';

    if (title.isEmpty) {
      switch (type) {
        case 'FRIEND_ADDED':
          final adderName = payload['adderName'] ?? 'A friend';
          title = 'Friend Added';
          body = '$adderName added you to their friends list.';
          break;
        case 'FRIEND_JOINED':
          final friendName = payload['friendName'] ?? 'Your friend';
          title = 'Friend Joined SplitUp!';
          body = '$friendName just joined SplitUp. Start sharing expenses!';
          break;
        case 'ADDED_TO_GROUP':
          final groupName = payload['groupName'] ?? 'a group';
          title = 'Added to Group';
          body = 'You were added to the group "$groupName".';
          break;
        case 'ADDED_TO_TRIP':
          final tripName = payload['tripName'] ?? 'a trip';
          title = 'Added to Trip';
          body = 'You were added to the trip "$tripName".';
          break;
        case 'EXPENSE_ADDED':
          final expTitle = payload['title'] ?? 'an expense';
          final owed = payload['owedPaise'] != null ? '₹${((payload['owedPaise'] as num) / 100).toStringAsFixed(0)}' : '';
          title = 'New Expense Split';
          body = 'New expense "$expTitle" was added. ${owed.isNotEmpty ? "Your share: $owed" : ""}';
          break;
        case 'SETTLEMENT_REQUESTED':
          final amt = payload['amountPaise'] != null ? '₹${((payload['amountPaise'] as num) / 100).toStringAsFixed(0)}' : '';
          title = 'Settlement Payment';
          body = 'A payment of $amt was recorded. Tap to confirm or decline.';
          break;
        case 'SETTLEMENT_CONFIRMED':
          title = 'Payment Confirmed';
          body = 'Your payment has been confirmed.';
          break;
        case 'SETTLEMENT_REJECTED':
          title = 'Payment Declined';
          body = 'Your payment was declined by the recipient.';
          break;
        case 'SETTLEMENT_OUTDATED':
          title = 'Settlement Outdated';
          body = 'The balance changed before settlement was confirmed.';
          break;
        default:
          title = 'SplitUp Notification';
          body = 'You have a new update.';
      }
    }

    final isRead = json['isRead'] as bool? ?? (json['readAt'] != null || json['read_at'] != null);

    return NotificationModel(
      id: json['id'] as String,
      type: type,
      title: title,
      body: body,
      isRead: isRead,
      actionState: json['actionState'] as String? ?? json['action_state'] as String?,
      actionResult: json['actionResult'] as String? ?? json['action_result'] as String?,
      payload: payload,
      createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at']) as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'body': body,
    'isRead': isRead,
    'actionState': actionState,
    'actionResult': actionResult,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
  };

  NotificationModel copyWith({
    String? id,
    String? type,
    String? title,
    String? body,
    bool? isRead,
    String? actionState,
    String? actionResult,
    Map<String, dynamic>? payload,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      isRead: isRead ?? this.isRead,
      actionState: actionState ?? this.actionState,
      actionResult: actionResult ?? this.actionResult,
      payload: payload ?? this.payload,
      createdAt: createdAt,
    );
  }
}

class NotificationsRepository {
  static const _storageKey = 'splitup_notifications_data_v1';
  bool _isLoaded = false;

  final List<NotificationModel> _items = [];

  Future<String> _getStorageKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      if (currentUserId != null && currentUserId.isNotEmpty) {
        return 'splitup_notifications_$currentUserId';
      }
    } catch (_) {}
    return _storageKey;
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _items.clear();
        _items.addAll(decoded.map((n) => NotificationModel.fromJson(n as Map<String, dynamic>)));
      } else {
        _items.clear();
      }

      // Purge any legacy dummy / sample notifications
      _items.removeWhere((n) =>
          n.id == 'notif_settle_sample' ||
          n.id == 'notif_1' ||
          n.id == 'notif_2' ||
          n.id.startsWith('notif_sample') ||
          n.payload?['settlementId'] == 'stl_sample_rahul' ||
          n.payload?['fromUserId'] == 'usr_rahul');

      // Also clean up legacy un-scoped key if present
      if (key != _storageKey && prefs.containsKey(_storageKey)) {
        await prefs.remove(_storageKey);
      }

      await _saveToStorage();
    } catch (_) {}
    _isLoaded = true;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();
      final raw = jsonEncode(_items.map((n) => n.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (_) {}
  }

  Future<List<NotificationModel>> fetchNotifications({bool forceRefresh = false}) async {
    await _ensureLoaded();

    try {
      final res = await ApiClient().get('/v1/notifications');
      if (res != null && res is Map<String, dynamic> && res.containsKey('data')) {
        final list = res['data'] as List<dynamic>;
        _items.clear();
        _items.addAll(list.map((n) => NotificationModel.fromJson(n as Map<String, dynamic>)));
        await _saveToStorage();
      }
    } catch (_) {
      // Offline fallback: keep cached items
    }

    return List.unmodifiable(_items);
  }

  Future<void> addNotification(NotificationModel notif) async {
    await _ensureLoaded();
    _items.insert(0, notif);
    await _saveToStorage();
  }

  Future<void> markRead(String id) async {
    await _ensureLoaded();
    final index = _items.indexWhere((n) => n.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(isRead: true);
      await _saveToStorage();
    }
    try {
      await ApiClient().patch('/v1/notifications/$id/read');
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    await _ensureLoaded();
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
    await _saveToStorage();
    try {
      await ApiClient().post('/v1/notifications/mark-all-read');
    } catch (_) {}
  }

  Future<void> deleteNotification(String id) async {
    await _ensureLoaded();
    _items.removeWhere((n) => n.id == id);
    await _saveToStorage();
    try {
      await ApiClient().delete('/v1/notifications/$id');
    } catch (_) {}
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    _items.clear();
    await _saveToStorage();
    try {
      await ApiClient().delete('/v1/notifications');
    } catch (_) {}
  }

  Future<void> updateActionState(String id, String actionState, {String? actionResult}) async {
    await _ensureLoaded();
    final index = _items.indexWhere((n) => n.id == id);
    if (index != -1) {
      _items[index] = _items[index].copyWith(
        actionState: actionState,
        actionResult: actionResult,
        isRead: true,
      );
      await _saveToStorage();
    }
  }

  Future<void> updateSettlementAction(String settlementId, String actionState, {String? actionResult}) async {
    await _ensureLoaded();
    for (int i = 0; i < _items.length; i++) {
      if (_items[i].payload?['settlementId'] == settlementId) {
        _items[i] = _items[i].copyWith(
          actionState: actionState,
          actionResult: actionResult,
          isRead: true,
        );
      }
    }
    await _saveToStorage();
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

  Future<List<NotificationModel>> refresh() async {
    final repo = ref.read(notificationsRepositoryProvider);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => repo.fetchNotifications(forceRefresh: true));
    return state.value ?? [];
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

  Future<void> deleteNotification(String id) async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.deleteNotification(id);
    ref.invalidateSelf();
  }

  Future<void> clearAll() async {
    final repo = ref.read(notificationsRepositoryProvider);
    await repo.clearAll();
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
