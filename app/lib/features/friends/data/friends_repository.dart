import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/friend_model.dart';
import '../../../core/mock/mock_data.dart';

class FriendsRepository {
  static const _defaultStorageKey = 'splitup_friends_data_v2';
  List<FriendModel> _friends = [];
  bool _isLoaded = false;

  FriendsRepository() {
    _initDefaultFriends();
  }

  void _initDefaultFriends() {
    _friends = MockDataRepository.friends.map((f) {
      return FriendModel(
        id: f.user.id,
        name: f.user.name,
        phoneE164: f.user.phone,
        photoUrl: f.user.photoUrl,
        isAppUser: !f.user.isPlaceholder,
        nickname: f.user.nickname,
        contactName: f.user.contactName,
        individualLedgerId: 'ldg_${f.user.id}',
        netPaise: f.netPaise,
        commonGroups: f.commonGroups,
      );
    }).toList();
  }

  Future<String> _getStorageKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('splitup_user_id');
      if (currentUserId != null && currentUserId != 'usr_arhaam') {
        return 'splitup_friends_$currentUserId';
      }
    } catch (_) {}
    return _defaultStorageKey;
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
        _friends = decoded.map((f) => FriendModel.fromJson(f as Map<String, dynamic>)).toList();
      } else {
        if (isRealNewUser) {
          _friends = [];
          await _saveToStorage();
        } else if (isDemoUser) {
          _initDefaultFriends();
        }
      }
    } catch (_) {}
    _isLoaded = true;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _getStorageKey();
      final raw = jsonEncode(_friends.map((f) => f.toJson()).toList());
      await prefs.setString(key, raw);
    } catch (_) {}
  }

  Future<List<FriendModel>> fetchFriends() async {
    await _ensureLoaded();
    return List.unmodifiable(_friends);
  }

  Future<FriendModel> addFriend({
    required String phone,
    String? name,
    String? contactName,
    bool? isAppUser,
  }) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 250));
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    final phoneE164 = cleaned.startsWith('91') ? '+$cleaned' : '+91$cleaned';

    bool isKnownAppUser = isAppUser ?? false;
    String friendName = name ?? 'Friend';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('splitup_registered_users_v2');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final p = item['phone']?.toString().replaceAll(RegExp(r'[^\d]'), '');
          if (p == cleaned) {
            isKnownAppUser = true;
            if (name == null || name.isEmpty) {
              friendName = item['name']?.toString() ?? friendName;
            }
            break;
          }
        }
      }
    } catch (_) {}

    final friendId = 'usr_${cleaned.length >= 6 ? cleaned.substring(cleaned.length - 6) : cleaned}';

    // If friend already exists in list, return existing
    final existingIdx = _friends.indexWhere((f) => f.id == friendId || f.phoneE164 == phoneE164);
    if (existingIdx != -1) {
      return _friends[existingIdx];
    }

    final friend = FriendModel(
      id: friendId,
      name: friendName,
      phoneE164: phoneE164,
      isAppUser: isKnownAppUser,
      contactName: contactName,
      individualLedgerId: 'ldg_$friendId',
      netPaise: 0,
    );

    _friends.insert(0, friend);
    await _saveToStorage();
    return friend;
  }

  Future<void> updateNickname(String friendId, String? nickname) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(nickname: nickname);
      await _saveToStorage();
    }
  }

  Future<void> removeFriend(String friendId) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 200));
    final friend = _friends.firstWhere((f) => f.id == friendId, orElse: () => throw Exception('Friend not found'));
    if (friend.netPaise != 0) {
      throw Exception('Cannot unfriend while balance is unsettled (balance: ₹${(friend.netPaise / 100).toStringAsFixed(2)})');
    }
    _friends.removeWhere((f) => f.id == friendId);
    await _saveToStorage();
  }

  void applySettlement(String friendId, int settledPaise) {
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      final current = _friends[index].netPaise;
      final newNet = current < 0 ? current + settledPaise : current - settledPaise;
      _friends[index] = _friends[index].copyWith(netPaise: newNet);
      _saveToStorage();
    }
  }

  void adjustBalance(String friendId, int diffPaise) {
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(
        netPaise: _friends[index].netPaise + diffPaise,
      );
      _saveToStorage();
    }
  }

  void setBalance(String friendId, int netPaise) {
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(
        netPaise: netPaise,
      );
      _saveToStorage();
    }
  }
}

final friendsRepositoryProvider = Provider<FriendsRepository>((ref) {
  return FriendsRepository();
});

class FriendsNotifier extends AsyncNotifier<List<FriendModel>> {
  @override
  Future<List<FriendModel>> build() async {
    final repo = ref.read(friendsRepositoryProvider);
    return repo.fetchFriends();
  }

  Future<FriendModel> addFriend({
    required String phone,
    String? name,
    String? contactName,
    bool? isAppUser,
  }) async {
    final repo = ref.read(friendsRepositoryProvider);
    final friend = await repo.addFriend(
      phone: phone,
      name: name,
      contactName: contactName,
      isAppUser: isAppUser,
    );
    ref.invalidateSelf();
    return friend;
  }

  Future<void> updateNickname(String friendId, String? nickname) async {
    final repo = ref.read(friendsRepositoryProvider);
    await repo.updateNickname(friendId, nickname);
    ref.invalidateSelf();
  }

  Future<void> removeFriend(String friendId) async {
    final repo = ref.read(friendsRepositoryProvider);
    await repo.removeFriend(friendId);
    ref.invalidateSelf();
  }
}

final friendsNotifierProvider = AsyncNotifierProvider<FriendsNotifier, List<FriendModel>>(() {
  return FriendsNotifier();
});
