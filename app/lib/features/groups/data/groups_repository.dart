import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/group_model.dart';
import '../../../core/mock/mock_data.dart';

class GroupsRepository {
  List<GroupModel> _groups = [];

  GroupsRepository() {
    // Initialize from rich mock data
    _groups = MockDataRepository.groups.map((g) {
      final members = g.members.map((u) {
        final isCreator = u.id == MockDataRepository.currentUser.id;
        final net = u.id == MockDataRepository.currentUser.id
            ? g.myNetPaise
            : (u.id == MockDataRepository.userRahul.id ? -g.myNetPaise : 0);

        return GroupMember(
          userId: u.id,
          name: u.name,
          phoneE164: u.phone,
          photoUrl: u.photoUrl,
          role: isCreator ? 'ADMIN' : 'MEMBER',
          netPaise: net,
          isAppUser: !u.isPlaceholder,
        );
      }).toList();

      return GroupModel(
        id: g.id,
        name: g.name,
        photoUrl: g.photoUrl,
        creatorUserId: MockDataRepository.currentUser.id,
        isAdmin: true,
        memberIds: members.map((m) => m.userId).toList(),
        members: members,
        myNetPaise: g.myNetPaise,
        totalSpentPaise: g.totalSpentPaise,
        lastActivity: g.lastActivity,
        createdAt: DateTime.now().subtract(const Duration(days: 14)).toIso8601String(),
      );
    }).toList();
  }

  Future<List<GroupModel>> fetchGroups() async {
    return List.unmodifiable(_groups);
  }

  Future<GroupModel> getGroupById(String groupId) async {
    return _groups.firstWhere(
      (g) => g.id == groupId,
      orElse: () => _groups.isNotEmpty
          ? _groups.first
          : GroupModel(
              id: groupId,
              name: 'Group',
              creatorUserId: 'usr_arhaam',
              isAdmin: true,
              myNetPaise: 0,
              totalSpentPaise: 0,
              createdAt: DateTime.now().toIso8601String(),
            ),
    );
  }

  Future<GroupModel> createGroup({
    required String name,
    required List<String> memberUserIds,
    String? photoUrl,
    String creatorUserId = 'usr_arhaam',
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final groupId = 'grp_${DateTime.now().millisecondsSinceEpoch}';
    final allUserIds = {creatorUserId, ...memberUserIds}.toList();

    final members = allUserIds.map((uid) {
      final isCreator = uid == creatorUserId;
      String memberName = 'Member';
      String phone = '+919999900000';
      bool isAppUser = true;

      if (uid == MockDataRepository.currentUser.id) {
        memberName = MockDataRepository.currentUser.name;
        phone = MockDataRepository.currentUser.phone;
      } else {
        final f = MockDataRepository.friends.where((fr) => fr.user.id == uid);
        if (f.isNotEmpty) {
          memberName = f.first.user.name;
          phone = f.first.user.phone;
          isAppUser = !f.first.user.isPlaceholder;
        }
      }

      return GroupMember(
        userId: uid,
        name: memberName,
        phoneE164: phone,
        role: isCreator ? 'ADMIN' : 'MEMBER',
        netPaise: 0,
        isAppUser: isAppUser,
      );
    }).toList();

    final newGroup = GroupModel(
      id: groupId,
      name: name.trim(),
      photoUrl: photoUrl,
      creatorUserId: creatorUserId,
      isAdmin: true,
      memberIds: allUserIds,
      members: members,
      myNetPaise: 0,
      totalSpentPaise: 0,
      lastActivity: 'Created just now',
      createdAt: DateTime.now().toIso8601String(),
    );

    _groups.insert(0, newGroup);
    return newGroup;
  }

  Future<void> updateGroup(
    String groupId, {
    String? name,
    String? photoUrl,
    String actorUserId = 'usr_arhaam',
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) throw Exception('Group not found');

    final group = _groups[index];
    if (actorUserId != group.creatorUserId) {
      throw Exception('Only group admins can update group details');
    }

    _groups[index] = GroupModel(
      id: group.id,
      name: name?.trim() ?? group.name,
      photoUrl: photoUrl ?? group.photoUrl,
      creatorUserId: group.creatorUserId,
      isAdmin: group.isAdmin,
      memberIds: group.memberIds,
      members: group.members,
      myNetPaise: group.myNetPaise,
      totalSpentPaise: group.totalSpentPaise,
      lastActivity: 'Updated recently',
      createdAt: group.createdAt,
    );
  }

  Future<void> addMember(
    String groupId,
    String newUserId, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) throw Exception('Group not found');

    final group = _groups[index];
    if (actorUserId != group.creatorUserId) {
      throw Exception('Only group admins can add members');
    }

    if (group.memberIds.contains(newUserId)) {
      throw Exception('User is already in this group');
    }

    String memberName = 'New Member';
    String phone = '+919999900000';
    bool isAppUser = true;
    final f = MockDataRepository.friends.where((fr) => fr.user.id == newUserId);
    if (f.isNotEmpty) {
      memberName = f.first.user.name;
      phone = f.first.user.phone;
      isAppUser = !f.first.user.isPlaceholder;
    }

    final newMember = GroupMember(
      userId: newUserId,
      name: memberName,
      phoneE164: phone,
      role: 'MEMBER',
      netPaise: 0,
      isAppUser: isAppUser,
    );

    final updatedMembers = [...group.members, newMember];
    final updatedIds = [...group.memberIds, newUserId];

    _groups[index] = GroupModel(
      id: group.id,
      name: group.name,
      photoUrl: group.photoUrl,
      creatorUserId: group.creatorUserId,
      isAdmin: group.isAdmin,
      memberIds: updatedIds,
      members: updatedMembers,
      myNetPaise: group.myNetPaise,
      totalSpentPaise: group.totalSpentPaise,
      lastActivity: 'Added $memberName',
      createdAt: group.createdAt,
    );
  }

  Future<void> removeMember(
    String groupId,
    String targetUserId, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) throw Exception('Group not found');

    final group = _groups[index];
    final isSelf = actorUserId == targetUserId;
    final isAdmin = actorUserId == group.creatorUserId;
    if (!isSelf && !isAdmin) {
      throw Exception('Only group admins can remove other members');
    }

    final targetMember = group.members.firstWhere(
      (m) => m.userId == targetUserId,
      orElse: () => throw Exception('User is not a member of this group'),
    );

    if (targetMember.netPaise != 0) {
      throw Exception('UNSETTLED_BALANCE: Cannot remove member with unsettled balance');
    }

    final updatedMembers = group.members.where((m) => m.userId != targetUserId).toList();
    final updatedIds = group.memberIds.where((id) => id != targetUserId).toList();

    _groups[index] = GroupModel(
      id: group.id,
      name: group.name,
      photoUrl: group.photoUrl,
      creatorUserId: group.creatorUserId,
      isAdmin: group.isAdmin,
      memberIds: updatedIds,
      members: updatedMembers,
      myNetPaise: group.myNetPaise,
      totalSpentPaise: group.totalSpentPaise,
      lastActivity: 'Member left',
      createdAt: group.createdAt,
    );
  }

  Future<void> deleteGroup(String groupId, {String actorUserId = 'usr_arhaam'}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index == -1) throw Exception('Group not found');

    final group = _groups[index];
    if (actorUserId != group.creatorUserId) {
      throw Exception('Only group admins can delete this group');
    }

    final hasUnsettled = group.members.any((m) => m.netPaise != 0);
    if (hasUnsettled) {
      throw Exception('UNSETTLED_BALANCE: Cannot delete group with unsettled balances');
    }

    _groups.removeAt(index);
  }

  GroupDashboardData getDashboard(String groupId) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    final group = index != -1 ? _groups[index] : null;
    final total = group?.totalSpentPaise ?? 2450000;

    return GroupDashboardData(
      totalSpentPaise: total,
      categories: const [
        CategoryBreakdownItem(category: 'Food & Drinks', totalPaise: 1100000, percentage: 45),
        CategoryBreakdownItem(category: 'Groceries', totalPaise: 650000, percentage: 26),
        CategoryBreakdownItem(category: 'Travel & Fuel', totalPaise: 420000, percentage: 17),
        CategoryBreakdownItem(category: 'Entertainment', totalPaise: 280000, percentage: 12),
      ],
      memberBars: group != null
          ? group.members.map((m) {
              return MemberBarItem(
                userId: m.userId,
                name: m.name,
                paidPaise: m.userId == 'usr_arhaam' ? 950000 : 500000,
                sharePaise: 612500,
              );
            }).toList()
          : const [
              MemberBarItem(userId: 'usr_arhaam', name: 'Arhaam', paidPaise: 950000, sharePaise: 612500),
              MemberBarItem(userId: 'usr_rahul', name: 'Rahul', paidPaise: 800000, sharePaise: 612500),
              MemberBarItem(userId: 'usr_priya', name: 'Priya', paidPaise: 400000, sharePaise: 612500),
              MemberBarItem(userId: 'usr_amit', name: 'Amit', paidPaise: 300000, sharePaise: 612500),
            ],
      spendingOverTime: const [
        SpendingOverTimeItem(date: 'Oct 01', totalPaise: 350000),
        SpendingOverTimeItem(date: 'Oct 03', totalPaise: 620000),
        SpendingOverTimeItem(date: 'Oct 05', totalPaise: 410000),
        SpendingOverTimeItem(date: 'Oct 07', totalPaise: 540000),
        SpendingOverTimeItem(date: 'Oct 09', totalPaise: 530000),
      ],
    );
  }

  GroupGraphData getGraph(String groupId, {bool simplified = true}) {
    final nodes = [
      const GraphNode(userId: 'usr_arhaam', name: 'Arhaam (You)', netPaise: -120000),
      const GraphNode(userId: 'usr_rahul', name: 'Rahul', netPaise: 240000),
      const GraphNode(userId: 'usr_priya', name: 'Priya', netPaise: 150000),
      const GraphNode(userId: 'usr_amit', name: 'Amit', netPaise: -270000),
    ];

    final links = simplified
        ? [
            const GraphLink(fromUserId: 'usr_arhaam', toUserId: 'usr_rahul', amountPaise: 120000, isPending: false),
            const GraphLink(fromUserId: 'usr_amit', toUserId: 'usr_rahul', amountPaise: 120000, isPending: false),
            const GraphLink(fromUserId: 'usr_amit', toUserId: 'usr_priya', amountPaise: 150000, isPending: false),
          ]
        : [
            const GraphLink(fromUserId: 'usr_arhaam', toUserId: 'usr_rahul', amountPaise: 80000, isPending: false),
            const GraphLink(fromUserId: 'usr_arhaam', toUserId: 'usr_priya', amountPaise: 40000, isPending: false),
            const GraphLink(fromUserId: 'usr_amit', toUserId: 'usr_rahul', amountPaise: 160000, isPending: false),
            const GraphLink(fromUserId: 'usr_amit', toUserId: 'usr_priya', amountPaise: 110000, isPending: false),
          ];

    return GroupGraphData(
      groupId: groupId,
      mode: simplified ? 'simplified' : 'actual',
      nodes: nodes,
      links: links,
    );
  }

  void updateGroupBalances(String groupId, String memberId, int settledPaise) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    if (index != -1) {
      final g = _groups[index];
      final current = g.myNetPaise;
      final newNet = current < 0 ? current + settledPaise : current - settledPaise;
      _groups[index] = GroupModel(
        id: g.id,
        name: g.name,
        photoUrl: g.photoUrl,
        creatorUserId: g.creatorUserId,
        isAdmin: g.isAdmin,
        memberIds: g.memberIds,
        members: g.members,
        myNetPaise: newNet,
        totalSpentPaise: g.totalSpentPaise,
        lastActivity: 'Settlement confirmed',
        createdAt: g.createdAt,
      );
    }
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  return GroupsRepository();
});

class GroupsNotifier extends AsyncNotifier<List<GroupModel>> {
  @override
  Future<List<GroupModel>> build() async {
    return ref.read(groupsRepositoryProvider).fetchGroups();
  }

  Future<void> createGroup({
    required String name,
    required List<String> memberUserIds,
    String? photoUrl,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).createGroup(
            name: name,
            memberUserIds: memberUserIds,
            photoUrl: photoUrl,
          );
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
  }

  Future<void> updateGroup(String groupId, {String? name, String? photoUrl}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).updateGroup(
            groupId,
            name: name,
            photoUrl: photoUrl,
          );
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
  }

  Future<void> addMember(String groupId, String newUserId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).addMember(groupId, newUserId);
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
  }

  Future<void> removeMember(String groupId, String targetUserId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).removeMember(groupId, targetUserId);
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
  }

  Future<void> deleteGroup(String groupId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).deleteGroup(groupId);
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
  }
}

final groupsNotifierProvider = AsyncNotifierProvider<GroupsNotifier, List<GroupModel>>(() {
  return GroupsNotifier();
});

final groupDetailProvider = FutureProvider.family<GroupModel, String>((ref, groupId) async {
  return ref.watch(groupsRepositoryProvider).getGroupById(groupId);
});

final groupDashboardProvider = Provider.family<GroupDashboardData, String>((ref, groupId) {
  return ref.watch(groupsRepositoryProvider).getDashboard(groupId);
});

final groupGraphProvider = Provider.family<GroupGraphData, ({String groupId, bool simplified})>((ref, arg) {
  return ref.watch(groupsRepositoryProvider).getGraph(arg.groupId, simplified: arg.simplified);
});
