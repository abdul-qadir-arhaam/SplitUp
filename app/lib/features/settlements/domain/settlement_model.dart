class SettlementModel {
  final String id;
  final String ledgerId;
  final String fromUserId;
  final String toUserId;
  final int amountPaise;
  final String method; // CASH | UPI | OFFSET | OTHER
  final String status; // PENDING | CONFIRMED | REJECTED | OUTDATED | CANCELLED
  final bool confirmedOnBehalf;
  final String? replacedById;
  final String createdBy;
  final String? respondedBy;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const SettlementModel({
    required this.id,
    required this.ledgerId,
    required this.fromUserId,
    required this.toUserId,
    required this.amountPaise,
    this.method = 'CASH',
    this.status = 'PENDING',
    this.confirmedOnBehalf = false,
    this.replacedById,
    required this.createdBy,
    this.respondedBy,
    required this.createdAt,
    this.respondedAt,
  });

  bool get isPending => status == 'PENDING';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isRejected => status == 'REJECTED';
  bool get isOutdated => status == 'OUTDATED';
  bool get isCancelled => status == 'CANCELLED';

  SettlementModel copyWith({
    String? status,
    String? respondedBy,
    DateTime? respondedAt,
    bool? confirmedOnBehalf,
    String? replacedById,
  }) {
    return SettlementModel(
      id: id,
      ledgerId: ledgerId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      amountPaise: amountPaise,
      method: method,
      status: status ?? this.status,
      confirmedOnBehalf: confirmedOnBehalf ?? this.confirmedOnBehalf,
      replacedById: replacedById ?? this.replacedById,
      createdBy: createdBy,
      respondedBy: respondedBy ?? this.respondedBy,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}
