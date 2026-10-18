import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/settlement_model.dart';
import '../../friends/data/friends_repository.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../../core/network/api_client.dart';

class SettlementsRepository {
  static const _storageKey = 'splitup_settlements_data_v3';
  final Ref _ref;
  List<SettlementModel> _settlements = [];
  bool _isLoaded = false;

  SettlementsRepository(this._ref);

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

  Future<String> _getStorageKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      if (currentUserId != null && currentUserId.isNotEmpty) {
        return 'splitup_settlements_$currentUserId';
      }
    } catch (_) {}
    return _storageKey;
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();

      // Clear settlement and notification caches once on first launch of this version (R9/f)
      final isCleaned = prefs.getBool('splitup_cache_cleared_v109') ?? false;
      if (!isCleaned) {
        await prefs.remove(key);
        await prefs.remove('splitup_settlements_data_v2');
        await prefs.remove(_storageKey);
        await prefs.setBool('splitup_cache_cleared_v109', true);
        _settlements = [];
        _isLoaded = true;
        return;
      }

      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _settlements = decoded
            .map((s) => SettlementModel.fromJson(s as Map<String, dynamic>))
            // Purge old local-only stl_<ms> settlements
            .where((s) => !RegExp(r'^stl_\d{13}$').hasMatch(s.id) && s.id != 'stl_sample_rahul')
            .toList();
      } else {
        _settlements = [];
      }
    } catch (_) {
      _settlements = [];
    }
    _isLoaded = true;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();
      final raw = jsonEncode(_settlements.map((s) => s.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (_) {}
  }

  Future<List<SettlementModel>> fetchAllSettlements() async {
    await _ensureLoaded();
    return List.unmodifiable(_settlements);
  }

  Future<List<SettlementModel>> fetchSettlementsForLedger(String ledgerId, {bool syncWithServer = true}) async {
    await _ensureLoaded();
    if (syncWithServer && ledgerId.isNotEmpty && ledgerId != 'ldg_default') {
      try {
        final res = await ApiClient().get('/v1/ledgers/$ledgerId/settlements');
        if (res != null && res is Map<String, dynamic> && res.containsKey('data')) {
          final list = res['data'] as List<dynamic>;
          final serverSettlements = list
              .map((item) => SettlementModel.fromJson(item as Map<String, dynamic>))
              .toList();

          // EXACT mirror: replace all local records for this ledger with authoritative server records
          _settlements.removeWhere((s) => s.ledgerId == ledgerId);
          _settlements.insertAll(0, serverSettlements);
          await _saveToStorage();
        }
      } catch (_) {}
    }
    return _settlements.where((s) => s.ledgerId == ledgerId).toList();
  }

  Future<SettlementModel?> getSettlementById(String id) async {
    await _ensureLoaded();
    final matches = _settlements.where((s) => s.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  Future<SettlementModel> createSettlement({
    required String ledgerId,
    required String toUserId,
    required int amountPaise,
    String method = 'CASH',
    bool isPlaceholderReceiver = false,
    String? idempotencyKey,
  }) async {
    await _ensureLoaded();

    final headers = idempotencyKey != null ? {'Idempotency-Key': idempotencyKey} : null;

    // R1: Only the server creates settlement IDs. App never invents one.
    // Call API and await authoritative response before saving anything locally.
    final res = await ApiClient().post(
      '/v1/settlements',
      {
        'ledgerId': ledgerId,
        'toUserId': toUserId,
        'amountPaise': amountPaise,
        'method': method,
      },
      headers,
    );

    if (res == null || res is! Map<String, dynamic> || !res.containsKey('data')) {
      throw const ApiException('Invalid response received from server');
    }

    final serverSettlement = SettlementModel.fromJson(res['data'] as Map<String, dynamic>);

    // Store server's authoritative record
    final idx = _settlements.indexWhere((s) => s.id == serverSettlement.id);
    if (idx != -1) {
      _settlements[idx] = serverSettlement;
    } else {
      _settlements.insert(0, serverSettlement);
    }
    await _saveToStorage();

    // Refetch friends to update authoritative balances
    try {
      await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(friendsNotifierProvider);

    return serverSettlement;
  }

  Future<SettlementModel> confirmSettlement(String settlementId) async {
    await _ensureLoaded();

    // Call server and await authoritative response
    final res = await ApiClient().post('/v1/settlements/$settlementId/confirm');
    if (res == null || res is! Map<String, dynamic> || !res.containsKey('data')) {
      throw const ApiException('Invalid response from server');
    }

    final serverSettlement = SettlementModel.fromJson(res['data'] as Map<String, dynamic>);

    final index = _settlements.indexWhere((s) => s.id == serverSettlement.id);
    if (index != -1) {
      _settlements[index] = serverSettlement;
    } else {
      _settlements.insert(0, serverSettlement);
    }
    await _saveToStorage();

    // Refetch friends, totals, and notifications
    try {
      await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(friendsNotifierProvider);

    try {
      await _ref.read(notificationsRepositoryProvider).fetchNotifications(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(notificationsNotifierProvider);

    return serverSettlement;
  }

  Future<SettlementModel> rejectSettlement(String settlementId) async {
    await _ensureLoaded();

    final res = await ApiClient().post('/v1/settlements/$settlementId/reject');
    if (res == null || res is! Map<String, dynamic> || !res.containsKey('data')) {
      throw const ApiException('Invalid response from server');
    }

    final serverSettlement = SettlementModel.fromJson(res['data'] as Map<String, dynamic>);

    final index = _settlements.indexWhere((s) => s.id == serverSettlement.id);
    if (index != -1) {
      _settlements[index] = serverSettlement;
    } else {
      _settlements.insert(0, serverSettlement);
    }
    await _saveToStorage();

    try {
      await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(friendsNotifierProvider);

    try {
      await _ref.read(notificationsRepositoryProvider).fetchNotifications(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(notificationsNotifierProvider);

    return serverSettlement;
  }

  Future<SettlementModel> cancelSettlement(String settlementId) async {
    await _ensureLoaded();

    final res = await ApiClient().post('/v1/settlements/$settlementId/cancel');
    if (res == null || res is! Map<String, dynamic> || !res.containsKey('data')) {
      throw const ApiException('Invalid response from server');
    }

    final serverSettlement = SettlementModel.fromJson(res['data'] as Map<String, dynamic>);

    final index = _settlements.indexWhere((s) => s.id == serverSettlement.id);
    if (index != -1) {
      _settlements[index] = serverSettlement;
    } else {
      _settlements.insert(0, serverSettlement);
    }
    await _saveToStorage();

    try {
      await _ref.read(notificationsRepositoryProvider).fetchNotifications(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(notificationsNotifierProvider);

    return serverSettlement;
  }

  Future<SettlementModel> resubmitSettlement(String settlementId, {int? newAmountPaise}) async {
    await _ensureLoaded();

    final body = <String, dynamic>{};
    if (newAmountPaise != null) {
      body['amountPaise'] = newAmountPaise;
    }

    final res = await ApiClient().post('/v1/settlements/$settlementId/resubmit', body);
    if (res == null || res is! Map<String, dynamic> || !res.containsKey('data')) {
      throw const ApiException('Invalid response from server');
    }

    final newSettlement = SettlementModel.fromJson(res['data'] as Map<String, dynamic>);

    // Update old settlement replacedById
    final oldIdx = _settlements.indexWhere((s) => s.id == settlementId);
    if (oldIdx != -1) {
      _settlements[oldIdx] = _settlements[oldIdx].copyWith(replacedById: newSettlement.id);
    }

    // Insert new settlement
    _settlements.insert(0, newSettlement);
    await _saveToStorage();

    try {
      await _ref.read(friendsRepositoryProvider).fetchFriends(forceRefresh: true);
    } catch (_) {}
    _ref.invalidate(friendsNotifierProvider);

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
    return repo.fetchAllSettlements();
  }

  Future<SettlementModel> createSettlement({
    required String ledgerId,
    required String toUserId,
    required int amountPaise,
    String method = 'CASH',
    bool isPlaceholderReceiver = false,
    String? idempotencyKey,
  }) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.createSettlement(
      ledgerId: ledgerId,
      toUserId: toUserId,
      amountPaise: amountPaise,
      method: method,
      isPlaceholderReceiver: isPlaceholderReceiver,
      idempotencyKey: idempotencyKey,
    );
    ref.invalidateSelf();
    return item;
  }

  Future<SettlementModel> confirmSettlement(String id) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.confirmSettlement(id);
    ref.invalidateSelf();
    return item;
  }

  Future<SettlementModel> rejectSettlement(String id) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.rejectSettlement(id);
    ref.invalidateSelf();
    return item;
  }

  Future<SettlementModel> cancelSettlement(String id) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.cancelSettlement(id);
    ref.invalidateSelf();
    return item;
  }

  Future<SettlementModel> resubmitSettlement(String id, {int? newAmountPaise}) async {
    final repo = ref.read(settlementsRepositoryProvider);
    final item = await repo.resubmitSettlement(id, newAmountPaise: newAmountPaise);
    ref.invalidateSelf();
    return item;
  }

  Future<void> syncSettlementsForLedger(String ledgerId) async {
    final repo = ref.read(settlementsRepositoryProvider);
    await repo.fetchSettlementsForLedger(ledgerId, syncWithServer: true);
    ref.invalidateSelf();
  }
}

final settlementsNotifierProvider = AsyncNotifierProvider<SettlementsNotifier, List<SettlementModel>>(() {
  return SettlementsNotifier();
});
