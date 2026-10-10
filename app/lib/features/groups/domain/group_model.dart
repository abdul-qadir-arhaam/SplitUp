class GroupMember {
  final String userId;
  final String name;
  final String phoneE164;
  final String? photoUrl;
  final String role; // 'ADMIN' | 'MEMBER'
  final int netPaise;
  final bool isAppUser;

  const GroupMember({
    required this.userId,
    required this.name,
    required this.phoneE164,
    this.photoUrl,
    required this.role,
    required this.netPaise,
    required this.isAppUser,
  });

  bool get isAdmin => role == 'ADMIN';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['userId'] as String,
      name: json['name'] as String? ?? 'Member',
      phoneE164: json['phoneE164'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      role: json['role'] as String? ?? 'MEMBER',
      netPaise: (json['netPaise'] as num?)?.toInt() ?? 0,
      isAppUser: json['isAppUser'] as bool? ?? true,
    );
  }
}

class GroupModel {
  final String id;
  final String name;
  final String? photoUrl;
  final String creatorUserId;
  final bool isAdmin;
  final List<String> memberIds;
  final List<GroupMember> members;
  final int myNetPaise;
  final int totalSpentPaise;
  final String lastActivity;
  final String createdAt;

  const GroupModel({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.creatorUserId,
    required this.isAdmin,
    this.memberIds = const [],
    this.members = const [],
    required this.myNetPaise,
    required this.totalSpentPaise,
    this.lastActivity = 'Active recently',
    required this.createdAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    final membersList = (json['members'] as List<dynamic>?)
            ?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];

    final memberIdsList = (json['memberIds'] as List<dynamic>?)
            ?.map((id) => id.toString())
            .toList() ??
        membersList.map((m) => m.userId).toList();

    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      photoUrl: json['photoUrl'] as String?,
      creatorUserId: json['creatorUserId'] as String? ?? '',
      isAdmin: json['isAdmin'] as bool? ?? false,
      memberIds: memberIdsList,
      members: membersList,
      myNetPaise: (json['myNetPaise'] as num?)?.toInt() ?? 0,
      totalSpentPaise: (json['totalSpentPaise'] as num?)?.toInt() ?? 0,
      lastActivity: json['lastActivity'] as String? ?? 'Active recently',
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}

class CategoryBreakdownItem {
  final String category;
  final int totalPaise;
  final int percentage;

  const CategoryBreakdownItem({
    required this.category,
    required this.totalPaise,
    required this.percentage,
  });

  factory CategoryBreakdownItem.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdownItem(
      category: json['category'] as String,
      totalPaise: (json['totalPaise'] as num?)?.toInt() ?? 0,
      percentage: (json['percentage'] as num?)?.toInt() ?? 0,
    );
  }
}

class MemberBarItem {
  final String userId;
  final String name;
  final int paidPaise;
  final int sharePaise;

  const MemberBarItem({
    required this.userId,
    required this.name,
    required this.paidPaise,
    required this.sharePaise,
  });

  factory MemberBarItem.fromJson(Map<String, dynamic> json) {
    return MemberBarItem(
      userId: json['userId'] as String,
      name: json['name'] as String? ?? 'Member',
      paidPaise: (json['paidPaise'] as num?)?.toInt() ?? 0,
      sharePaise: (json['sharePaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class SpendingOverTimeItem {
  final String date;
  final int totalPaise;

  const SpendingOverTimeItem({
    required this.date,
    required this.totalPaise,
  });

  factory SpendingOverTimeItem.fromJson(Map<String, dynamic> json) {
    return SpendingOverTimeItem(
      date: json['date'] as String,
      totalPaise: (json['totalPaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupDashboardData {
  final int totalSpentPaise;
  final List<CategoryBreakdownItem> categories;
  final List<MemberBarItem> memberBars;
  final List<SpendingOverTimeItem> spendingOverTime;

  const GroupDashboardData({
    required this.totalSpentPaise,
    required this.categories,
    required this.memberBars,
    required this.spendingOverTime,
  });

  factory GroupDashboardData.fromJson(Map<String, dynamic> json) {
    final rawCats = (json['categories'] ?? json['categoryBreakdown']) as List<dynamic>? ?? [];
    final rawBars = (json['memberBars'] ?? json['memberMetrics']) as List<dynamic>? ?? [];
    final rawTime = (json['spendingOverTime'] as List<dynamic>?) ?? [];

    return GroupDashboardData(
      totalSpentPaise: (json['totalSpentPaise'] as num?)?.toInt() ?? 0,
      categories: rawCats.map((c) => CategoryBreakdownItem.fromJson(c as Map<String, dynamic>)).toList(),
      memberBars: rawBars.map((b) => MemberBarItem.fromJson(b as Map<String, dynamic>)).toList(),
      spendingOverTime: rawTime.map((t) => SpendingOverTimeItem.fromJson(t as Map<String, dynamic>)).toList(),
    );
  }
}

class GraphNode {
  final String userId;
  final String name;
  final int netPaise;

  const GraphNode({
    required this.userId,
    required this.name,
    required this.netPaise,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      userId: json['userId'] as String,
      name: json['name'] as String? ?? 'User',
      netPaise: (json['netPaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class GraphLink {
  final String? settlementId;
  final String fromUserId;
  final String toUserId;
  final int amountPaise;
  final bool isPending;
  final String? method;

  const GraphLink({
    this.settlementId,
    required this.fromUserId,
    required this.toUserId,
    required this.amountPaise,
    required this.isPending,
    this.method,
  });

  factory GraphLink.fromJson(Map<String, dynamic> json) {
    return GraphLink(
      settlementId: json['settlementId'] as String?,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      isPending: json['isPending'] as bool? ?? false,
      method: json['method'] as String?,
    );
  }
}

class GroupGraphData {
  final String groupId;
  final String mode; // 'simplified' | 'actual'
  final List<GraphNode> nodes;
  final List<GraphLink> links;

  const GroupGraphData({
    required this.groupId,
    required this.mode,
    required this.nodes,
    required this.links,
  });

  factory GroupGraphData.fromJson(Map<String, dynamic> json) {
    final nodesList = (json['nodes'] as List<dynamic>?)
            ?.map((n) => GraphNode.fromJson(n as Map<String, dynamic>))
            .toList() ??
        const [];
    final linksList = (json['links'] as List<dynamic>?)
            ?.map((l) => GraphLink.fromJson(l as Map<String, dynamic>))
            .toList() ??
        const [];

    return GroupGraphData(
      groupId: json['groupId'] as String,
      mode: json['mode'] as String? ?? 'simplified',
      nodes: nodesList,
      links: linksList,
    );
  }
}
