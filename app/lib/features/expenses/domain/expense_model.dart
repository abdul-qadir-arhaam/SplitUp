class ExpensePayer {
  final String userId;
  final int paidPaise;

  const ExpensePayer({required this.userId, required this.paidPaise});

  Map<String, dynamic> toJson() => {'userId': userId, 'paidPaise': paidPaise};

  factory ExpensePayer.fromJson(Map<String, dynamic> json) => ExpensePayer(
        userId: json['userId'] as String,
        paidPaise: json['paidPaise'] as int,
      );
}

class ExpenseSplit {
  final String userId;
  final int owedPaise;
  final bool included;
  final int? splitValue;

  const ExpenseSplit({
    required this.userId,
    required this.owedPaise,
    required this.included,
    this.splitValue,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'owedPaise': owedPaise,
        'included': included,
        if (splitValue != null) 'splitValue': splitValue,
      };

  factory ExpenseSplit.fromJson(Map<String, dynamic> json) => ExpenseSplit(
        userId: json['userId'] as String,
        owedPaise: json['owedPaise'] as int,
        included: json['included'] as bool? ?? true,
        splitValue: json['splitValue'] as int?,
      );
}

class ExpenseActivityItem {
  final String id;
  final String action;
  final String actorUserId;
  final DateTime createdAt;
  final Map<String, dynamic>? payload;

  const ExpenseActivityItem({
    required this.id,
    required this.action,
    required this.actorUserId,
    required this.createdAt,
    this.payload,
  });
}

class ExpenseModel {
  final String id;
  final String ledgerId;
  final String title;
  final int totalPaise;
  final String category;
  final String splitType;
  final String expenseDate;
  final String? note;
  final List<ExpensePayer> payers;
  final List<ExpenseSplit> splits;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deletedBy;
  final bool isDisputed;

  const ExpenseModel({
    required this.id,
    required this.ledgerId,
    required this.title,
    required this.totalPaise,
    required this.category,
    required this.splitType,
    required this.expenseDate,
    this.note,
    required this.payers,
    required this.splits,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deletedBy,
    this.isDisputed = false,
  });

  ExpenseModel copyWith({
    String? title,
    int? totalPaise,
    String? category,
    String? splitType,
    List<ExpensePayer>? payers,
    List<ExpenseSplit>? splits,
    bool? isDisputed,
    DateTime? deletedAt,
    String? deletedBy,
  }) {
    return ExpenseModel(
      id: id,
      ledgerId: ledgerId,
      title: title ?? this.title,
      totalPaise: totalPaise ?? this.totalPaise,
      category: category ?? this.category,
      splitType: splitType ?? this.splitType,
      expenseDate: expenseDate,
      note: note,
      payers: payers ?? this.payers,
      splits: splits ?? this.splits,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      isDisputed: isDisputed ?? this.isDisputed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ledgerId': ledgerId,
        'title': title,
        'totalPaise': totalPaise,
        'category': category,
        'splitType': splitType,
        'expenseDate': expenseDate,
        'note': note,
        'payers': payers.map((p) => p.toJson()).toList(),
        'splits': splits.map((s) => s.toJson()).toList(),
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deletedBy': deletedBy,
        'isDisputed': isDisputed,
      };

  factory ExpenseModel.fromJson(Map<String, dynamic> json) => ExpenseModel(
        id: json['id'] as String,
        ledgerId: json['ledgerId'] as String,
        title: json['title'] as String,
        totalPaise: (json['totalPaise'] as num).toInt(),
        category: json['category'] as String,
        splitType: json['splitType'] as String? ?? 'EQUAL',
        expenseDate: json['expenseDate'] as String,
        note: json['note'] as String?,
        payers: (json['payers'] as List<dynamic>?)
                ?.map((p) => ExpensePayer.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        splits: (json['splits'] as List<dynamic>?)
                ?.map((s) => ExpenseSplit.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        createdBy: json['createdBy'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        deletedAt: json['deletedAt'] != null
            ? DateTime.tryParse(json['deletedAt'] as String)
            : null,
        deletedBy: json['deletedBy'] as String?,
        isDisputed: json['isDisputed'] as bool? ?? false,
      );
}
