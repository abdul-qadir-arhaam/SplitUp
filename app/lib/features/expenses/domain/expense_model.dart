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
}
