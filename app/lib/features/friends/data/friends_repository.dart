import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/friend_model.dart';
import '../../../core/mock/mock_data.dart';

class FriendsRepository {
  List<FriendModel> _friends = [];

  FriendsRepository() {
    // Initial populate from existing mock data so user has immediate rich experience
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

  Future<List<FriendModel>> fetchFriends() async {
    return List.unmodifiable(_friends);
  }

  Future<FriendModel> addFriend({
    required String phone,
    String? name,
    String? contactName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    final phoneE164 = cleaned.startsWith('91') ? '+$cleaned' : '+91$cleaned';

    // Check if phone matches known mock app users
    final isKnownAppUser = cleaned.endsWith('1') || cleaned.endsWith('2') || cleaned.endsWith('3');
    final friendId = 'usr_${cleaned.length >= 6 ? cleaned.substring(cleaned.length - 6) : cleaned}';

    final friend = FriendModel(
      id: friendId,
      name: name ?? (isKnownAppUser ? 'App User' : 'New Contact'),
      phoneE164: phoneE164,
      isAppUser: isKnownAppUser,
      contactName: contactName,
      individualLedgerId: 'ldg_$friendId',
      netPaise: 0,
    );

    _friends.insert(0, friend);
    return friend;
  }

  Future<void> updateNickname(String friendId, String? nickname) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(nickname: nickname);
    }
  }

  Future<void> removeFriend(String friendId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final friend = _friends.firstWhere((f) => f.id == friendId, orElse: () => throw Exception('Friend not found'));
    if (friend.netPaise != 0) {
      throw Exception('Cannot unfriend while balance is unsettled (balance: ₹${(friend.netPaise / 100).toStringAsFixed(2)})');
    }
    _friends.removeWhere((f) => f.id == friendId);
  }

  void applySettlement(String friendId, int settledPaise) {
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      final current = _friends[index].netPaise;
      final newNet = current < 0 ? current + settledPaise : current - settledPaise;
      _friends[index] = _friends[index].copyWith(netPaise: newNet);
    }
  }

  void adjustBalance(String friendId, int diffPaise) {
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(
        netPaise: _friends[index].netPaise + diffPaise,
      );
    }
  }

  void setBalance(String friendId, int netPaise) {
    final index = _friends.indexWhere((f) => f.id == friendId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(
        netPaise: netPaise,
      );
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
  }) async {
    final repo = ref.read(friendsRepositoryProvider);
    final friend = await repo.addFriend(phone: phone, name: name, contactName: contactName);
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
