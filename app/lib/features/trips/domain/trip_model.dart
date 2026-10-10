import '../../groups/domain/group_model.dart';
import '../../expenses/domain/expense_model.dart';

class TripMember {
  final String userId;
  final String name;
  final String phoneE164;
  final String? photoUrl;
  final String role; // 'ADMIN' | 'MEMBER'
  final int netPaise;
  final bool isAppUser;

  const TripMember({
    required this.userId,
    required this.name,
    required this.phoneE164,
    this.photoUrl,
    required this.role,
    required this.netPaise,
    required this.isAppUser,
  });

  bool get isAdmin => role == 'ADMIN';

  factory TripMember.fromJson(Map<String, dynamic> json) {
    return TripMember(
      userId: json['userId'] as String,
      name: json['name'] as String? ?? 'Member',
      phoneE164: json['phoneE164'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      role: json['role'] as String? ?? 'MEMBER',
      netPaise: (json['netPaise'] as num?)?.toInt() ?? 0,
      isAppUser: json['isAppUser'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'phoneE164': phoneE164,
        'photoUrl': photoUrl,
        'role': role,
        'netPaise': netPaise,
        'isAppUser': isAppUser,
      };
}

class TripBudgetMeter {
  final int budgetPaise;
  final int totalSpentPaise;
  final int remainingPaise;
  final double spentPercent;
  final String level; // 'UNDER_60' | '60_TO_80' | '80_TO_100' | 'OVER_100'
  final String statusMessage;
  final int? daysTotal;
  final int? daysElapsed;
  final int? daysRemaining;
  final int? remainingPerDayPaise;
  final bool isOverBudget;

  const TripBudgetMeter({
    required this.budgetPaise,
    required this.totalSpentPaise,
    required this.remainingPaise,
    required this.spentPercent,
    required this.level,
    required this.statusMessage,
    this.daysTotal,
    this.daysElapsed,
    this.daysRemaining,
    this.remainingPerDayPaise,
    required this.isOverBudget,
  });

  factory TripBudgetMeter.fromJson(Map<String, dynamic> json) {
    return TripBudgetMeter(
      budgetPaise: (json['budgetPaise'] as num?)?.toInt() ?? 0,
      totalSpentPaise: (json['totalSpentPaise'] as num?)?.toInt() ?? 0,
      remainingPaise: (json['remainingPaise'] as num?)?.toInt() ?? 0,
      spentPercent: (json['spentPercent'] as num?)?.toDouble() ?? 0.0,
      level: json['level'] as String? ?? 'UNDER_60',
      statusMessage: json['statusMessage'] as String? ?? 'On track',
      daysTotal: (json['daysTotal'] as num?)?.toInt(),
      daysElapsed: (json['daysElapsed'] as num?)?.toInt(),
      daysRemaining: (json['daysRemaining'] as num?)?.toInt(),
      remainingPerDayPaise: (json['remainingPerDayPaise'] as num?)?.toInt(),
      isOverBudget: json['isOverBudget'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'budgetPaise': budgetPaise,
        'totalSpentPaise': totalSpentPaise,
        'remainingPaise': remainingPaise,
        'spentPercent': spentPercent,
        'level': level,
        'statusMessage': statusMessage,
        'daysTotal': daysTotal,
        'daysElapsed': daysElapsed,
        'daysRemaining': daysRemaining,
        'remainingPerDayPaise': remainingPerDayPaise,
        'isOverBudget': isOverBudget,
      };
}

class TripModel {
  final String id;
  final String name;
  final String? photoUrl;
  final int budgetPaise;
  final String? startDate;
  final String? endDate;
  final String status; // 'ACTIVE' | 'COMPLETED'
  final bool isCompleted;
  final String creatorUserId;
  final bool isAdmin;
  final int membersCount;
  final int myNetPaise;
  final int totalSpentPaise;
  final String createdAt;
  final List<TripMember> members;
  final TripBudgetMeter? budgetMeter;

  const TripModel({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.budgetPaise,
    this.startDate,
    this.endDate,
    this.status = 'ACTIVE',
    required this.isCompleted,
    required this.creatorUserId,
    required this.isAdmin,
    required this.membersCount,
    required this.myNetPaise,
    required this.totalSpentPaise,
    required this.createdAt,
    this.members = const [],
    this.budgetMeter,
  });

  double get budgetProgress =>
      budgetPaise > 0 ? (totalSpentPaise / budgetPaise).clamp(0.0, 1.5) : 0.0;

  factory TripModel.fromJson(Map<String, dynamic> json) {
    final membersList = (json['members'] as List<dynamic>?)
            ?.map((m) => TripMember.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];

    return TripModel(
      id: json['id'] as String,
      name: json['name'] as String,
      photoUrl: json['photoUrl'] as String?,
      budgetPaise: (json['budgetPaise'] as num?)?.toInt() ?? 0,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      isCompleted: json['isCompleted'] as bool? ?? (json['status'] == 'COMPLETED'),
      creatorUserId: json['creatorUserId'] as String? ?? '',
      isAdmin: json['isAdmin'] as bool? ?? false,
      membersCount: (json['membersCount'] as num?)?.toInt() ?? membersList.length,
      myNetPaise: (json['myNetPaise'] as num?)?.toInt() ?? 0,
      totalSpentPaise: (json['totalSpentPaise'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
      members: membersList,
      budgetMeter: json['budgetMeter'] != null
          ? TripBudgetMeter.fromJson(json['budgetMeter'] as Map<String, dynamic>)
          : null,
    );
  }

  TripModel copyWith({
    String? name,
    String? photoUrl,
    int? budgetPaise,
    String? startDate,
    String? endDate,
    String? status,
    bool? isCompleted,
    List<TripMember>? members,
    TripBudgetMeter? budgetMeter,
    int? myNetPaise,
    int? totalSpentPaise,
  }) {
    return TripModel(
      id: id,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      budgetPaise: budgetPaise ?? this.budgetPaise,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      isCompleted: isCompleted ?? this.isCompleted,
      creatorUserId: creatorUserId,
      isAdmin: isAdmin,
      membersCount: members?.length ?? membersCount,
      myNetPaise: myNetPaise ?? this.myNetPaise,
      totalSpentPaise: totalSpentPaise ?? this.totalSpentPaise,
      createdAt: createdAt,
      members: members ?? this.members,
      budgetMeter: budgetMeter ?? this.budgetMeter,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'photoUrl': photoUrl,
        'budgetPaise': budgetPaise,
        'startDate': startDate,
        'endDate': endDate,
        'status': status,
        'isCompleted': isCompleted,
        'creatorUserId': creatorUserId,
        'isAdmin': isAdmin,
        'membersCount': membersCount,
        'myNetPaise': myNetPaise,
        'totalSpentPaise': totalSpentPaise,
        'createdAt': createdAt,
        'members': members.map((m) => m.toJson()).toList(),
        'budgetMeter': budgetMeter?.toJson(),
      };
}

class TripDailySpendingItem {
  final String date;
  final String dayLabel;
  final int totalPaise;

  const TripDailySpendingItem({
    required this.date,
    required this.dayLabel,
    required this.totalPaise,
  });

  factory TripDailySpendingItem.fromJson(Map<String, dynamic> json) {
    return TripDailySpendingItem(
      date: json['date'] as String,
      dayLabel: json['dayLabel'] as String? ?? json['date'] as String,
      totalPaise: (json['totalPaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class TripMemberSpendItem {
  final String userId;
  final String name;
  final int paidPaise;
  final int sharePaise;
  final int netPaise;

  const TripMemberSpendItem({
    required this.userId,
    required this.name,
    required this.paidPaise,
    required this.sharePaise,
    required this.netPaise,
  });

  factory TripMemberSpendItem.fromJson(Map<String, dynamic> json) {
    return TripMemberSpendItem(
      userId: json['userId'] as String,
      name: json['name'] as String? ?? 'Member',
      paidPaise: (json['paidPaise'] as num?)?.toInt() ?? 0,
      sharePaise: (json['sharePaise'] as num?)?.toInt() ?? 0,
      netPaise: (json['netPaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class TripDashboardData {
  final TripModel trip;
  final TripBudgetMeter budgetMeter;
  final List<CategoryBreakdownItem> categoryBreakdown;
  final List<TripDailySpendingItem> dailySpending;
  final List<TripMemberSpendItem> memberSpends;
  final List<ExpenseModel> expenses;

  const TripDashboardData({
    required this.trip,
    required this.budgetMeter,
    required this.categoryBreakdown,
    required this.dailySpending,
    required this.memberSpends,
    required this.expenses,
  });
}
