import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/money/paise.dart';
import '../domain/group_model.dart';
import '../../../core/mock/mock_data.dart';
import '../../expenses/domain/expense_model.dart';
import '../../expenses/data/expenses_repository.dart';

class GroupsRepository {
  static const _storageKey = 'splitup_groups_data_v2';
  List<GroupModel> _groups = [];
  bool _isLoaded = false;

  GroupsRepository() {
    _initDefaultGroups();
  }

  void _initDefaultGroups() {
    // Initialize from rich mock data
    _groups = MockDataRepository.groups.map((g) {
      final members = g.members.map((u) {
        final isCreator = u.id == MockDataRepository.currentUser.id;
        int net = 0;
        if (g.id == 'grp_friday') {
          if (u.id == 'usr_arhaam') {
            net = -120000; // Arhaam owes ₹1,200
          } else if (u.id == 'usr_rahul') {
            net = 240000; // Rahul is owed ₹2,400
          } else if (u.id == 'usr_priya') {
            net = 150000; // Priya is owed ₹1,500 (Amit owes Priya)
          } else if (u.id == 'usr_amit') {
            net = -270000; // Amit owes Priya ₹1,500 and Rahul ₹1,200
          } else if (u.id == 'usr_sneha') {
            net = 0; // Sneha settled
          }
        } else if (g.id == 'grp_flat402') {
          if (u.id == 'usr_arhaam') {
            net = 245000; // Arhaam is owed ₹2,450
          } else if (u.id == 'usr_priya') {
            net = -122500;
          } else if (u.id == 'usr_amit') {
            net = -122500;
          }
        } else {
          net = u.id == MockDataRepository.currentUser.id
              ? g.myNetPaise
              : (u.id == MockDataRepository.userRahul.id ? -g.myNetPaise : 0);
        }

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

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _groups = decoded.map((g) => GroupModel.fromJson(g as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    _isLoaded = true;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_groups.map((g) => g.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (_) {}
  }

  Future<List<GroupModel>> fetchGroups() async {
    await _ensureLoaded();
    return List.unmodifiable(_groups);
  }

  Future<GroupModel> getGroupById(String groupId) async {
    await _ensureLoaded();
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
    await _ensureLoaded();
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
    await _saveToStorage();
    return newGroup;
  }

  Future<void> updateGroup(
    String groupId, {
    String? name,
    String? photoUrl,
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
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
    await _saveToStorage();
  }

  Future<void> addMember(
    String groupId,
    String newUserId, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
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
    await _saveToStorage();
  }

  /// Checks whether a member has any pending debts they need to pay to anyone.
  /// Checks current group graph, other groups, and friendships.
  /// Returns a descriptive message if debts exist, or null if clear.
  String? checkPendingDebts(String userId, {String? groupId}) {
    // 1. Check in current group
    if (groupId != null) {
      final grpIndex = _groups.indexWhere((g) => g.id == groupId);
      if (grpIndex != -1) {
        final grp = _groups[grpIndex];
        final member = grp.members.where((m) => m.userId == userId);
        if (member.isNotEmpty) {
          final m = member.first;
          if (m.netPaise < 0) {
            final graph = getGraph(groupId);
            final debts = graph.links.where((l) => l.fromUserId == userId && l.amountPaise > 0).toList();
            if (debts.isNotEmpty) {
              final breakdown = debts.map((d) {
                final toName = graph.nodes.firstWhere(
                  (n) => n.userId == d.toUserId,
                  orElse: () => GraphNode(userId: d.toUserId, name: 'friend', netPaise: 0),
                ).name;
                return 'owes $toName ${formatPaise(d.amountPaise)}';
              }).join(' and ');
              return '$breakdown in ${grp.name}';
            }
            return 'owes ${formatPaise(m.netPaise.abs())} in ${grp.name}';
          } else if (m.netPaise > 0) {
            return 'is owed ${formatPaise(m.netPaise)} in ${grp.name}';
          }
        }
      }
    }

    // 2. Check across all groups
    for (final grp in _groups) {
      if (grp.id == groupId) continue;
      final member = grp.members.where((m) => m.userId == userId);
      if (member.isNotEmpty) {
        final m = member.first;
        if (m.netPaise < 0) {
          return 'owes ${formatPaise(m.netPaise.abs())} in ${grp.name}';
        } else if (m.netPaise > 0) {
          return 'is owed ${formatPaise(m.netPaise)} in ${grp.name}';
        }
      }
    }

    return null;
  }

  Future<void> removeMember(
    String groupId,
    String targetUserId, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
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

    final pendingDebt = checkPendingDebts(targetUserId, groupId: groupId);
    if (pendingDebt != null || targetMember.netPaise != 0) {
      throw Exception('UNSETTLED_BALANCE: Cannot remove member: ${pendingDebt ?? "unsettled balance"}');
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
    await _saveToStorage();
  }

  Future<void> deleteGroup(String groupId, {String actorUserId = 'usr_arhaam'}) async {
    await _ensureLoaded();
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
    await _saveToStorage();
  }

  GroupModel? getGroupByIdSync(String groupId) {
    final index = _groups.indexWhere((g) => g.id == groupId);
    return index != -1 ? _groups[index] : null;
  }

  static ({
    int totalSpentPaise,
    int myNetPaise,
    List<GroupMember> updatedMembers,
  }) calculateGroupMetrics(GroupModel group, List<ExpenseModel> groupExpenses) {
    if (groupExpenses.isEmpty) {
      if (group.id == 'grp_friday' || group.id == 'grp_flat402') {
        return (
          totalSpentPaise: group.totalSpentPaise,
          myNetPaise: group.myNetPaise,
          updatedMembers: group.members,
        );
      }
      final zeroMembers = group.members.map((m) => GroupMember(
        userId: m.userId,
        name: m.name,
        phoneE164: m.phoneE164,
        photoUrl: m.photoUrl,
        role: m.role,
        netPaise: 0,
        isAppUser: m.isAppUser,
      )).toList();
      return (
        totalSpentPaise: 0,
        myNetPaise: 0,
        updatedMembers: zeroMembers,
      );
    }

    int totalSpent = 0;
    final Map<String, int> paidByUser = {for (final m in group.members) m.userId: 0};
    final Map<String, int> shareByUser = {for (final m in group.members) m.userId: 0};

    for (final exp in groupExpenses) {
      if (exp.deletedAt != null) continue;
      totalSpent += exp.totalPaise;
      for (final p in exp.payers) {
        paidByUser[p.userId] = (paidByUser[p.userId] ?? 0) + p.paidPaise;
      }
      for (final s in exp.splits) {
        if (s.included) {
          shareByUser[s.userId] = (shareByUser[s.userId] ?? 0) + s.owedPaise;
        }
      }
    }

    final updatedMembers = group.members.map((m) {
      final paid = paidByUser[m.userId] ?? 0;
      final share = shareByUser[m.userId] ?? 0;
      final net = paid - share;
      return GroupMember(
        userId: m.userId,
        name: m.name,
        phoneE164: m.phoneE164,
        photoUrl: m.photoUrl,
        role: m.role,
        netPaise: net,
        isAppUser: m.isAppUser,
      );
    }).toList();

    final myNet = (paidByUser['usr_arhaam'] ?? 0) - (shareByUser['usr_arhaam'] ?? 0);

    return (
      totalSpentPaise: totalSpent,
      myNetPaise: myNet,
      updatedMembers: updatedMembers,
    );
  }

  static List<GraphLink> calculateSimplifiedDebts(List<GraphNode> nodes) {
    final debtors = <({String userId, int amount})>[];
    final creditors = <({String userId, int amount})>[];

    for (final n in nodes) {
      if (n.netPaise < 0) {
        debtors.add((userId: n.userId, amount: -n.netPaise));
      } else if (n.netPaise > 0) {
        creditors.add((userId: n.userId, amount: n.netPaise));
      }
    }

    debtors.sort((a, b) => b.amount != a.amount ? b.amount.compareTo(a.amount) : a.userId.compareTo(b.userId));
    creditors.sort((a, b) => b.amount != a.amount ? b.amount.compareTo(a.amount) : a.userId.compareTo(b.userId));

    final links = <GraphLink>[];
    int dIdx = 0;
    int cIdx = 0;

    var curDebtors = debtors.map((d) => (userId: d.userId, amount: d.amount)).toList();
    var curCreditors = creditors.map((c) => (userId: c.userId, amount: c.amount)).toList();

    while (dIdx < curDebtors.length && cIdx < curCreditors.length) {
      final d = curDebtors[dIdx];
      final c = curCreditors[cIdx];

      final amt = d.amount < c.amount ? d.amount : c.amount;
      if (amt > 0) {
        links.add(GraphLink(
          fromUserId: d.userId,
          toUserId: c.userId,
          amountPaise: amt,
          isPending: false,
        ));
      }

      curDebtors[dIdx] = (userId: d.userId, amount: d.amount - amt);
      curCreditors[cIdx] = (userId: c.userId, amount: c.amount - amt);

      if (curDebtors[dIdx].amount == 0) dIdx++;
      if (curCreditors[cIdx].amount == 0) cIdx++;
    }

    return links;
  }

  static List<GraphLink> calculatePairwiseDebts(List<ExpenseModel> expenses) {
    final Map<String, Map<String, int>> matrix = {};

    for (final exp in expenses) {
      if (exp.totalPaise <= 0) continue;
      for (final payer in exp.payers) {
        if (payer.paidPaise <= 0) continue;
        for (final split in exp.splits) {
          if (!split.included || split.owedPaise <= 0) continue;
          if (split.userId == payer.userId) continue;

          final shareOwedToPayer = (split.owedPaise * payer.paidPaise / exp.totalPaise).round();
          if (shareOwedToPayer > 0) {
            matrix.putIfAbsent(split.userId, () => {});
            matrix[split.userId]![payer.userId] =
                (matrix[split.userId]![payer.userId] ?? 0) + shareOwedToPayer;
          }
        }
      }
    }

    final Set<String> allUsers = {};
    for (final u in matrix.keys) {
      allUsers.add(u);
      allUsers.addAll(matrix[u]!.keys);
    }

    final userList = allUsers.toList();
    final List<GraphLink> links = [];

    for (int i = 0; i < userList.length; i++) {
      for (int j = i + 1; j < userList.length; j++) {
        final u1 = userList[i];
        final u2 = userList[j];
        final u1OwesU2 = matrix[u1]?[u2] ?? 0;
        final u2OwesU1 = matrix[u2]?[u1] ?? 0;

        final net = u1OwesU2 - u2OwesU1;
        if (net > 0) {
          links.add(GraphLink(fromUserId: u1, toUserId: u2, amountPaise: net, isPending: false));
        } else if (net < 0) {
          links.add(GraphLink(fromUserId: u2, toUserId: u1, amountPaise: -net, isPending: false));
        }
      }
    }

    return links;
  }

  static String _categoryLabel(String cat) {
    switch (cat.toLowerCase()) {
      case 'food':
        return 'Food & Drinks';
      case 'travel':
        return 'Travel & Fuel';
      case 'stay':
        return 'Stay';
      case 'tickets':
        return 'Tickets';
      case 'shopping':
        return 'Shopping';
      case 'groceries':
        return 'Groceries';
      case 'entertainment':
        return 'Entertainment';
      default:
        return cat.isNotEmpty ? (cat[0].toUpperCase() + cat.substring(1)) : 'Other';
    }
  }

  GroupDashboardData computeDashboard(GroupModel group, List<ExpenseModel> groupExpenses) {
    if (groupExpenses.isEmpty) {
      if (group.id == 'grp_friday') {
        return getDashboard(group.id);
      }
      return GroupDashboardData(
        totalSpentPaise: 0,
        categories: const [],
        memberBars: group.members.map((m) {
          return MemberBarItem(
            userId: m.userId,
            name: m.name,
            paidPaise: 0,
            sharePaise: 0,
          );
        }).toList(),
        spendingOverTime: const [],
      );
    }

    final totalSpent = groupExpenses.fold(0, (sum, e) => sum + e.totalPaise);

    final Map<String, int> catMap = {};
    for (final exp in groupExpenses) {
      final catKey = exp.category.isNotEmpty ? exp.category : 'other';
      catMap[catKey] = (catMap[catKey] ?? 0) + exp.totalPaise;
    }
    final categories = catMap.entries.map((entry) {
      final pct = totalSpent > 0 ? ((entry.value * 100) / totalSpent).round() : 0;
      return CategoryBreakdownItem(
        category: _categoryLabel(entry.key),
        totalPaise: entry.value,
        percentage: pct,
      );
    }).toList();

    final Map<String, int> paidMap = {for (final m in group.members) m.userId: 0};
    final Map<String, int> shareMap = {for (final m in group.members) m.userId: 0};
    for (final exp in groupExpenses) {
      for (final p in exp.payers) {
        paidMap[p.userId] = (paidMap[p.userId] ?? 0) + p.paidPaise;
      }
      for (final s in exp.splits) {
        if (s.included) {
          shareMap[s.userId] = (shareMap[s.userId] ?? 0) + s.owedPaise;
        }
      }
    }

    final memberBars = group.members.map((m) {
      return MemberBarItem(
        userId: m.userId,
        name: m.name,
        paidPaise: paidMap[m.userId] ?? 0,
        sharePaise: shareMap[m.userId] ?? 0,
      );
    }).toList();

    final Map<String, int> dateMap = {};
    for (final exp in groupExpenses) {
      final d = exp.expenseDate.isNotEmpty ? exp.expenseDate : 'Recent';
      dateMap[d] = (dateMap[d] ?? 0) + exp.totalPaise;
    }
    final spendingOverTime = dateMap.entries.map((entry) {
      return SpendingOverTimeItem(date: entry.key, totalPaise: entry.value);
    }).toList();

    return GroupDashboardData(
      totalSpentPaise: totalSpent,
      categories: categories,
      memberBars: memberBars,
      spendingOverTime: spendingOverTime,
    );
  }

  GroupGraphData computeGraph(GroupModel group, List<ExpenseModel> groupExpenses, {bool simplified = true}) {
    if (groupExpenses.isEmpty) {
      if (group.id == 'grp_friday') {
        return getGraph(group.id, simplified: simplified);
      }
      final nodes = group.members.map((m) {
        return GraphNode(
          userId: m.userId,
          name: m.userId == 'usr_arhaam' ? '${m.name} (You)' : m.name,
          netPaise: 0,
        );
      }).toList();
      return GroupGraphData(
        groupId: group.id,
        mode: simplified ? 'simplified' : 'actual',
        nodes: nodes,
        links: const [],
      );
    }

    final Map<String, int> paidMap = {for (final m in group.members) m.userId: 0};
    final Map<String, int> shareMap = {for (final m in group.members) m.userId: 0};

    for (final exp in groupExpenses) {
      for (final p in exp.payers) {
        paidMap[p.userId] = (paidMap[p.userId] ?? 0) + p.paidPaise;
      }
      for (final s in exp.splits) {
        if (s.included) {
          shareMap[s.userId] = (shareMap[s.userId] ?? 0) + s.owedPaise;
        }
      }
    }

    final nodes = group.members.map((m) {
      final net = (paidMap[m.userId] ?? 0) - (shareMap[m.userId] ?? 0);
      return GraphNode(
        userId: m.userId,
        name: m.userId == 'usr_arhaam' ? '${m.name} (You)' : m.name,
        netPaise: net,
      );
    }).toList();

    final links = simplified
        ? calculateSimplifiedDebts(nodes)
        : calculatePairwiseDebts(groupExpenses);

    return GroupGraphData(
      groupId: group.id,
      mode: simplified ? 'simplified' : 'actual',
      nodes: nodes,
      links: links,
    );
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
    ref.invalidate(groupDetailProvider(groupId));
    ref.invalidate(groupDashboardProvider(groupId));
  }

  Future<void> addMember(String groupId, String newUserId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).addMember(groupId, newUserId);
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
    ref.invalidate(groupDetailProvider(groupId));
    ref.invalidate(groupDashboardProvider(groupId));
  }

  Future<void> removeMember(String groupId, String targetUserId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).removeMember(groupId, targetUserId);
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
    ref.invalidate(groupDetailProvider(groupId));
    ref.invalidate(groupDashboardProvider(groupId));
  }

  Future<void> deleteGroup(String groupId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(groupsRepositoryProvider).deleteGroup(groupId);
      return ref.read(groupsRepositoryProvider).fetchGroups();
    });
    ref.invalidate(groupDetailProvider(groupId));
    ref.invalidate(groupDashboardProvider(groupId));
  }
}

final groupsNotifierProvider = AsyncNotifierProvider<GroupsNotifier, List<GroupModel>>(() {
  return GroupsNotifier();
});

final groupDetailProvider = FutureProvider.family<GroupModel, String>((ref, groupId) async {
  final repo = ref.watch(groupsRepositoryProvider);
  final group = await repo.getGroupById(groupId);

  final asyncExpenses = ref.watch(expensesNotifierProvider);
  final allExpenses = asyncExpenses.maybeWhen(
    data: (list) => list,
    orElse: () => <ExpenseModel>[],
  );
  final groupExpenses = allExpenses.where((e) => e.ledgerId == groupId && e.deletedAt == null).toList();

  if (groupExpenses.isEmpty) {
    return group;
  }

  final metrics = GroupsRepository.calculateGroupMetrics(group, groupExpenses);
  return group.copyWith(
    totalSpentPaise: metrics.totalSpentPaise,
    myNetPaise: metrics.myNetPaise,
    members: metrics.updatedMembers,
  );
});

final groupDashboardProvider = Provider.family<GroupDashboardData, String>((ref, groupId) {
  final group = ref.watch(groupDetailProvider(groupId)).maybeWhen(
    data: (g) => g,
    orElse: () => ref.watch(groupsRepositoryProvider).getGroupByIdSync(groupId) ?? GroupModel(id: groupId, name: 'Group', creatorUserId: 'usr_arhaam', isAdmin: true, memberIds: const [], members: const [], myNetPaise: 0, totalSpentPaise: 0, lastActivity: '', createdAt: ''),
  );
  final allExpenses = ref.watch(expensesNotifierProvider).maybeWhen(
    data: (list) => list,
    orElse: () => <ExpenseModel>[],
  );
  final groupExpenses = allExpenses.where((e) => e.ledgerId == groupId && e.deletedAt == null).toList();
  return ref.watch(groupsRepositoryProvider).computeDashboard(group, groupExpenses);
});

final groupGraphProvider = Provider.family<GroupGraphData, ({String groupId, bool simplified})>((ref, arg) {
  final group = ref.watch(groupDetailProvider(arg.groupId)).maybeWhen(
    data: (g) => g,
    orElse: () => ref.watch(groupsRepositoryProvider).getGroupByIdSync(arg.groupId) ?? GroupModel(id: arg.groupId, name: 'Group', creatorUserId: 'usr_arhaam', isAdmin: true, memberIds: const [], members: const [], myNetPaise: 0, totalSpentPaise: 0, lastActivity: '', createdAt: ''),
  );
  final allExpenses = ref.watch(expensesNotifierProvider).maybeWhen(
    data: (list) => list,
    orElse: () => <ExpenseModel>[],
  );
  final groupExpenses = allExpenses.where((e) => e.ledgerId == arg.groupId && e.deletedAt == null).toList();
  return ref.watch(groupsRepositoryProvider).computeGraph(group, groupExpenses, simplified: arg.simplified);
});
