class OffsetSuggestion {
  final String toUserId;
  final String toUserName;
  final String groupLedgerId;
  final String individualLedgerId;
  final int groupDebtPaise;
  final int individualCreditPaise;
  final int maxOffsetPaise;
  final int remainingGroupDebtPaise;

  const OffsetSuggestion({
    required this.toUserId,
    required this.toUserName,
    required this.groupLedgerId,
    required this.individualLedgerId,
    required this.groupDebtPaise,
    required this.individualCreditPaise,
    required this.maxOffsetPaise,
    required this.remainingGroupDebtPaise,
  });

  factory OffsetSuggestion.fromJson(Map<String, dynamic> json) {
    return OffsetSuggestion(
      toUserId: json['toUserId'] as String,
      toUserName: json['toUserName'] as String? ?? 'Friend',
      groupLedgerId: json['groupLedgerId'] as String,
      individualLedgerId: json['individualLedgerId'] as String,
      groupDebtPaise: (json['groupDebtPaise'] as num?)?.toInt() ?? 0,
      individualCreditPaise: (json['individualCreditPaise'] as num?)?.toInt() ?? 0,
      maxOffsetPaise: (json['maxOffsetPaise'] as num?)?.toInt() ?? 0,
      remainingGroupDebtPaise: (json['remainingGroupDebtPaise'] as num?)?.toInt() ?? 0,
    );
  }
}

class OffsetRecordModel {
  final String id;
  final String groupLedgerId;
  final String individualLedgerId;
  final String fromUserId;
  final String toUserId;
  final int amountPaise;
  final String status; // 'PENDING' | 'CONFIRMED' | 'REJECTED' | 'OUTDATED'
  final DateTime createdAt;

  const OffsetRecordModel({
    required this.id,
    required this.groupLedgerId,
    required this.individualLedgerId,
    required this.fromUserId,
    required this.toUserId,
    required this.amountPaise,
    required this.status,
    required this.createdAt,
  });

  bool get isPending => status == 'PENDING';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isRejected => status == 'REJECTED';
  bool get isOutdated => status == 'OUTDATED';

  factory OffsetRecordModel.fromJson(Map<String, dynamic> json) {
    return OffsetRecordModel(
      id: json['id'] as String,
      groupLedgerId: json['groupLedgerId'] as String,
      individualLedgerId: json['individualLedgerId'] as String,
      fromUserId: json['fromUserId'] as String,
      toUserId: json['toUserId'] as String,
      amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'PENDING',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
