import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/offset_model.dart';
import '../../groups/data/groups_repository.dart';
import '../../friends/data/friends_repository.dart';
import '../../../core/mock/mock_data.dart';

class OffsetsRepository {
  final Ref _ref;
  final List<OffsetRecordModel> _offsets = [];

  OffsetsRepository(this._ref);

  Future<List<OffsetSuggestion>> getSuggestions(String groupLedgerId) async {
    final groups = await _ref.read(groupsRepositoryProvider).fetchGroups();
    final group = groups.firstWhere(
      (g) => g.id == groupLedgerId,
      orElse: () => groups.isNotEmpty ? groups.first : throw Exception('Group not found'),
    );

    // If caller doesn't owe money in group, no offset possible
    if (group.myNetPaise >= 0) return const [];

    final groupDebt = -group.myNetPaise;
    final friends = await _ref.read(friendsRepositoryProvider).fetchFriends();
    final suggestions = <OffsetSuggestion>[];

    for (final member in group.members) {
      if (member.userId == MockDataRepository.currentUser.id) continue;

      // Check individual balance with this member
      final f = friends.where((fr) => fr.id == member.userId);
      if (f.isNotEmpty) {
        final friend = f.first;
        // If friend owes me individually (netPaise > 0)
        if (friend.netPaise > 0) {
          final maxOffset = groupDebt < friend.netPaise ? groupDebt : friend.netPaise;
          suggestions.add(
            OffsetSuggestion(
              toUserId: friend.id,
              toUserName: friend.resolvedName,
              groupLedgerId: groupLedgerId,
              individualLedgerId: friend.individualLedgerId,
              groupDebtPaise: groupDebt,
              individualCreditPaise: friend.netPaise,
              maxOffsetPaise: maxOffset,
              remainingGroupDebtPaise: groupDebt - maxOffset,
            ),
          );
        }
      }
    }

    return suggestions;
  }

  Future<OffsetRecordModel> createOffset({
    required String groupLedgerId,
    required String toUserId,
    required int amountPaise,
  }) async {
    final offsetId = 'ofs_${DateTime.now().millisecondsSinceEpoch}';

    final offset = OffsetRecordModel(
      id: offsetId,
      groupLedgerId: groupLedgerId,
      individualLedgerId: 'ldg_$toUserId',
      fromUserId: MockDataRepository.currentUser.id,
      toUserId: toUserId,
      amountPaise: amountPaise,
      status: 'PENDING',
      createdAt: DateTime.now(),
    );

    _offsets.insert(0, offset);
    return offset;
  }

  Future<OffsetRecordModel> confirmOffset(String offsetId) async {
    final index = _offsets.indexWhere((o) => o.id == offsetId);
    if (index == -1) throw Exception('Offset not found');

    final offset = _offsets[index];
    if (offset.status != 'PENDING') {
      throw Exception('Offset cannot be confirmed (current status: ${offset.status})');
    }

    // Atomically update both ledgers
    await _ref.read(groupsRepositoryProvider).updateGroupBalances(
          offset.groupLedgerId,
          offset.toUserId,
          offset.amountPaise,
        );

    _ref.read(friendsRepositoryProvider).applySettlement(
          offset.toUserId,
          offset.amountPaise,
        );

    final updated = OffsetRecordModel(
      id: offset.id,
      groupLedgerId: offset.groupLedgerId,
      individualLedgerId: offset.individualLedgerId,
      fromUserId: offset.fromUserId,
      toUserId: offset.toUserId,
      amountPaise: offset.amountPaise,
      status: 'CONFIRMED',
      createdAt: offset.createdAt,
    );

    _offsets[index] = updated;
    return updated;
  }

  Future<OffsetRecordModel> rejectOffset(String offsetId) async {
    final index = _offsets.indexWhere((o) => o.id == offsetId);
    if (index == -1) throw Exception('Offset not found');

    final offset = _offsets[index];
    final updated = OffsetRecordModel(
      id: offset.id,
      groupLedgerId: offset.groupLedgerId,
      individualLedgerId: offset.individualLedgerId,
      fromUserId: offset.fromUserId,
      toUserId: offset.toUserId,
      amountPaise: offset.amountPaise,
      status: 'REJECTED',
      createdAt: offset.createdAt,
    );

    _offsets[index] = updated;
    return updated;
  }
}

final offsetsRepositoryProvider = Provider<OffsetsRepository>((ref) {
  return OffsetsRepository(ref);
});

final offsetSuggestionsProvider = FutureProvider.family<List<OffsetSuggestion>, String>((ref, groupId) async {
  return ref.watch(offsetsRepositoryProvider).getSuggestions(groupId);
});
