import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    return NotificationModel(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      isRead: json['isRead'] as bool? ?? false,
      actionState: json['actionState'] as String?,
      actionResult: json['actionResult'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
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

  Future<List<NotificationModel>> fetchNotifications() async {
    await _ensureLoaded();
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
  }

  Future<void> markAllRead() async {
    await _ensureLoaded();
    for (int i = 0; i < _items.length; i++) {
      _items[i] = _items[i].copyWith(isRead: true);
    }
    await _saveToStorage();
  }

  Future<void> deleteNotification(String id) async {
    await _ensureLoaded();
    _items.removeWhere((n) => n.id == id);
    await _saveToStorage();
  }

  Future<void> clearAll() async {
    await _ensureLoaded();
    _items.clear();
    await _saveToStorage();
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
