import 'package:flutter/foundation.dart';

@immutable
class MockUser {
  final String id;
  final String name;
  final String phone;
  final String? nickname;
  final String? contactName;
  final String? photoUrl;
  final bool isPlaceholder;

  const MockUser({
    required this.id,
    required this.name,
    required this.phone,
    this.nickname,
    this.contactName,
    this.photoUrl,
    this.isPlaceholder = false,
  });

  String get displayName => nickname ?? contactName ?? name;
}

@immutable
class MockFriend {
  final MockUser user;
  final int netPaise; // positive = owed to me, negative = I owe
  final String? lastActivity;
  final List<String> commonGroups;

  const MockFriend({
    required this.user,
    required this.netPaise,
    this.lastActivity,
    this.commonGroups = const [],
  });
}

@immutable
class MockGroup {
  final String id;
  final String name;
  final String? photoUrl;
  final List<MockUser> members;
  final int myNetPaise;
  final int totalSpentPaise;
  final String lastActivity;

  const MockGroup({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.members,
    required this.myNetPaise,
    required this.totalSpentPaise,
    required this.lastActivity,
  });
}

@immutable
class MockTrip {
  final String id;
  final String name;
  final String? photoUrl;
  final int budgetPaise;
  final int spentPaise;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCompleted;
  final List<MockUser> members;
  final int myNetPaise;

  const MockTrip({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.budgetPaise,
    required this.spentPaise,
    this.startDate,
    this.endDate,
    this.isCompleted = false,
    required this.members,
    required this.myNetPaise,
  });

  double get budgetProgress =>
      budgetPaise > 0 ? (spentPaise / budgetPaise).clamp(0.0, 1.5) : 0.0;

  String get budgetLevel {
    final pct = budgetProgress * 100;
    if (pct < 60) return 'normal';
    if (pct < 80) return 'warning';
    if (pct < 100) return 'alert';
    return 'exceeded';
  }
}

@immutable
class MockExpense {
  final String id;
  final String ledgerId;
  final String title;
  final int totalPaise;
  final String category;
  final DateTime date;
  final MockUser paidBy;
  final List<MockUser> splitAmong;
  final String splitType;
  final List<MockUser> excludedMembers;

  const MockExpense({
    required this.id,
    required this.ledgerId,
    required this.title,
    required this.totalPaise,
    required this.category,
    required this.date,
    required this.paidBy,
    required this.splitAmong,
    this.splitType = 'EQUAL',
    this.excludedMembers = const [],
  });
}

@immutable
class MockSettlement {
  final String id;
  final String ledgerId;
  final MockUser fromUser;
  final MockUser toUser;
  final int amountPaise;
  final String status; // PENDING, CONFIRMED, REJECTED, OUTDATED
  final DateTime createdAt;
  final String method;

  const MockSettlement({
    required this.id,
    required this.ledgerId,
    required this.fromUser,
    required this.toUser,
    required this.amountPaise,
    required this.status,
    required this.createdAt,
    this.method = 'UPI',
  });
}

@immutable
class MockNotification {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final String type;
  final String? actionState; // OPEN, DONE, EXPIRED
  final MockSettlement? relatedSettlement;
  final bool isRead;

  const MockNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.type,
    this.actionState,
    this.relatedSettlement,
    this.isRead = false,
  });
}

class MockDataRepository {
  static const currentUser = MockUser(
    id: 'usr_arhaam',
    name: 'Arhaam',
    phone: '+919876543210',
  );

  static const userRahul = MockUser(
    id: 'usr_rahul',
    name: 'Rahul Sharma',
    phone: '+919812345678',
    nickname: 'Rahul (College)',
  );

  static const userPriya = MockUser(
    id: 'usr_priya',
    name: 'Priya Patel',
    phone: '+919823456789',
  );

  static const userAmit = MockUser(
    id: 'usr_amit',
    name: 'Amit Verma',
    phone: '+919834567890',
  );

  static const userSneha = MockUser(
    id: 'usr_sneha',
    name: 'Sneha Nair',
    phone: '+919845678901',
  );

  static const userVikram = MockUser(
    id: 'usr_vikram',
    name: 'Vikram Singh',
    phone: '+919856789012',
    isPlaceholder: true,
  );

  static final List<MockFriend> friends = [
    const MockFriend(
      user: userRahul,
      netPaise: -125000, // I owe Rahul ₹1,250
      lastActivity: 'Dinner at Fisherman\'s Wharf',
      commonGroups: ['Goa Trip', 'Friday Gang'],
    ),
    const MockFriend(
      user: userPriya,
      netPaise: 340000, // Priya owes me ₹3,400
      lastActivity: 'Electricity Bill',
      commonGroups: ['Flat 402'],
    ),
    const MockFriend(
      user: userSneha,
      netPaise: 85000, // Sneha owes me ₹850
      lastActivity: 'Movie tickets',
      commonGroups: ['Friday Gang'],
    ),
    const MockFriend(
      user: userVikram,
      netPaise: -45000, // I owe Vikram ₹450
      lastActivity: 'Chai & Snacks',
      commonGroups: [],
    ),
    const MockFriend(
      user: userAmit,
      netPaise: 0, // Settled up
      lastActivity: 'Settled on Oct 8',
      commonGroups: ['Friday Gang'],
    ),
  ];

  static final List<MockGroup> groups = [
    const MockGroup(
      id: 'grp_friday',
      name: 'Friday Gang',
      members: [currentUser, userRahul, userPriya, userAmit, userSneha],
      myNetPaise: -120000, // I owe ₹1,200
      totalSpentPaise: 4850000, // ₹48,500
      lastActivity: 'Rahul paid ₹4,000 for Dinner',
    ),
    const MockGroup(
      id: 'grp_flat402',
      name: 'Flat 402',
      members: [currentUser, userPriya, userAmit],
      myNetPaise: 245000, // I am owed ₹2,450
      totalSpentPaise: 3200000, // ₹32,000
      lastActivity: 'Priya paid ₹2,100 for Groceries',
    ),
  ];

  static final List<MockTrip> trips = [
    MockTrip(
      id: 'trip_goa',
      name: 'Goa Trip',
      budgetPaise: 5000000, // ₹50,000
      spentPaise: 3840000, // ₹38,400 (76.8% -> amber warning)
      startDate: DateTime(2026, 10, 12),
      endDate: DateTime(2026, 10, 16),
      members: const [currentUser, userRahul, userPriya, userSneha],
      myNetPaise: -125000, // I owe ₹1,250
    ),
    MockTrip(
      id: 'trip_manali',
      name: 'Manali Trek',
      budgetPaise: 3500000,
      spentPaise: 3320000,
      startDate: DateTime(2026, 5, 10),
      endDate: DateTime(2026, 5, 15),
      isCompleted: true,
      members: const [currentUser, userAmit, userRahul],
      myNetPaise: 0,
    ),
  ];

  static final List<MockExpense> expenses = [
    MockExpense(
      id: 'exp_1',
      ledgerId: 'trip_goa',
      title: 'Fisherman\'s Wharf Dinner',
      totalPaise: 640000, // ₹6,400
      category: 'food',
      date: DateTime(2026, 10, 13),
      paidBy: userRahul,
      splitAmong: const [currentUser, userRahul, userPriya, userSneha],
    ),
    MockExpense(
      id: 'exp_2',
      ledgerId: 'trip_goa',
      title: 'Scooter Rentals (2 Days)',
      totalPaise: 320000, // ₹3,200
      category: 'travel',
      date: DateTime(2026, 10, 12),
      paidBy: currentUser,
      splitAmong: const [currentUser, userRahul, userPriya, userSneha],
    ),
    MockExpense(
      id: 'exp_3',
      ledgerId: 'grp_flat402',
      title: 'WiFi & Electricity Bill',
      totalPaise: 210000, // ₹2,100
      category: 'other',
      date: DateTime(2026, 10, 9),
      paidBy: userPriya,
      splitAmong: const [currentUser, userPriya, userAmit],
    ),
    MockExpense(
      id: 'exp_4',
      ledgerId: 'usr_rahul',
      title: 'Movie Tickets & Popcorn',
      totalPaise: 150000, // ₹1,500
      category: 'tickets',
      date: DateTime(2026, 10, 7),
      paidBy: userRahul,
      splitAmong: const [currentUser, userRahul],
    ),
  ];

  static final List<MockSettlement> settlements = [
    MockSettlement(
      id: 'stl_1',
      ledgerId: 'usr_rahul',
      fromUser: currentUser,
      toUser: userRahul,
      amountPaise: 125000, // ₹1,250
      status: 'PENDING',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    MockSettlement(
      id: 'stl_2',
      ledgerId: 'usr_sneha',
      fromUser: userSneha,
      toUser: currentUser,
      amountPaise: 50000, // ₹500
      status: 'CONFIRMED',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  static final List<MockNotification> notifications = [
    MockNotification(
      id: 'notif_1',
      title: 'Payment Confirmation',
      message: 'Arhaam sent you a payment confirmation of ₹1,250 via UPI.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 45)),
      type: 'SETTLEMENT_REQUESTED',
      actionState: 'OPEN',
      relatedSettlement: settlements[0],
    ),
    MockNotification(
      id: 'notif_2',
      title: 'Budget Alert (Goa Trip)',
      message: 'Goa Trip has reached 76% of its ₹50,000 budget.',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      type: 'BUDGET_WARNING',
    ),
    MockNotification(
      id: 'notif_3',
      title: 'Friend Joined',
      message: 'Vikram Singh joined SplitUp! All prior dues are now linked.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      type: 'FRIEND_JOINED',
      isRead: true,
    ),
  ];
}
