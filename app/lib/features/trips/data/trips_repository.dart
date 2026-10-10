import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/money/paise.dart';
import '../../groups/domain/group_model.dart';
import '../../expenses/domain/expense_model.dart';
import '../domain/trip_model.dart';

class TripsRepository {
  static const _storageKey = 'splitup_trips_data_v1';
  List<TripModel> _trips = [];
  bool _isLoaded = false;

  TripsRepository() {
    _initDefaultTrips();
  }

  Future<void> _ensureLoaded() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        _trips = decoded.map((t) => TripModel.fromJson(t as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    _isLoaded = true;
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_trips.map((t) => t.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (_) {}
  }

  void _initDefaultTrips() {
    final creator = MockDataRepository.currentUser;
    final rahul = MockDataRepository.userRahul;
    final priya = MockDataRepository.userPriya;
    final sneha = MockDataRepository.userSneha;

    final members = [
      TripMember(
        userId: creator.id,
        name: creator.name,
        phoneE164: creator.phone,
        role: 'ADMIN',
        netPaise: 420000,
        isAppUser: true,
      ),
      TripMember(
        userId: rahul.id,
        name: rahul.name,
        phoneE164: rahul.phone,
        role: 'MEMBER',
        netPaise: -180000,
        isAppUser: true,
      ),
      TripMember(
        userId: priya.id,
        name: priya.name,
        phoneE164: priya.phone,
        role: 'MEMBER',
        netPaise: -240000,
        isAppUser: true,
      ),
      TripMember(
        userId: sneha.id,
        name: sneha.name,
        phoneE164: sneha.phone,
        role: 'MEMBER',
        netPaise: 0,
        isAppUser: true,
      ),
    ];

    // Goa Vacation: Rs 50,000 budget with Rs 38,400 spent (76.8% -> 60_TO_80 Amber level)
    final goaMeter = computeBudgetMeter(
      5000000,
      3840000,
      '2026-10-12',
      '2026-10-16',
    );

    final goaTrip = TripModel(
      id: 'trp_goa_2026',
      name: 'Goa Vacation',
      budgetPaise: 5000000,
      startDate: '2026-10-12',
      endDate: '2026-10-16',
      status: 'ACTIVE',
      isCompleted: false,
      creatorUserId: creator.id,
      isAdmin: true,
      membersCount: 4,
      myNetPaise: 420000,
      totalSpentPaise: 3840000,
      createdAt: '2026-10-01T10:00:00Z',
      members: members,
      budgetMeter: goaMeter,
    );

    // Completed Ladakh Trip
    final ladakhMeter = computeBudgetMeter(
      8000000,
      7600000,
      '2026-06-10',
      '2026-06-20',
    );

    final ladakhTrip = TripModel(
      id: 'trp_ladakh_2026',
      name: 'Ladakh Road Trip',
      budgetPaise: 8000000,
      startDate: '2026-06-10',
      endDate: '2026-06-20',
      status: 'COMPLETED',
      isCompleted: true,
      creatorUserId: creator.id,
      isAdmin: true,
      membersCount: 4,
      myNetPaise: 0,
      totalSpentPaise: 7600000,
      createdAt: '2026-05-15T09:00:00Z',
      members: members,
      budgetMeter: ladakhMeter,
    );

    _trips = [goaTrip, ladakhTrip];
  }

  static TripBudgetMeter computeBudgetMeter(
    int budgetPaise,
    int totalSpentPaise,
    String? startDate,
    String? endDate,
  ) {
    final remainingPaise = budgetPaise - totalSpentPaise;
    final double spentPercent = budgetPaise > 0
        ? double.parse(((totalSpentPaise / budgetPaise) * 100).toStringAsFixed(1))
        : 0.0;

    String level;
    String statusMessage;

    if (spentPercent < 60) {
      level = 'UNDER_60';
      statusMessage = 'On track';
    } else if (spentPercent < 80) {
      level = '60_TO_80';
      statusMessage = 'Heads up';
    } else if (spentPercent <= 100) {
      level = '80_TO_100';
      statusMessage = 'Warning, remaining ${formatPaise(remainingPaise)}';
    } else {
      level = 'OVER_100';
      final overPaise = totalSpentPaise - budgetPaise;
      statusMessage = 'Over budget by ${formatPaise(overPaise)}';
    }

    int? daysTotal;
    int? daysElapsed;
    int? daysRemaining;
    int? remainingPerDayPaise;

    if (startDate != null && endDate != null) {
      try {
        final start = DateTime.parse(startDate);
        final end = DateTime.parse(endDate);
        daysTotal = end.difference(start).inDays + 1;
        if (daysTotal <= 0) daysTotal = 1;

        final now = DateTime.now();
        if (now.isBefore(start)) {
          daysElapsed = 0;
          daysRemaining = daysTotal;
        } else if (now.isAfter(end)) {
          daysElapsed = daysTotal;
          daysRemaining = 0;
        } else {
          daysElapsed = now.difference(start).inDays + 1;
          daysRemaining = (daysTotal - daysElapsed).clamp(1, daysTotal);
        }

        if (daysRemaining > 0 && remainingPaise > 0) {
          remainingPerDayPaise = remainingPaise ~/ daysRemaining;
        } else {
          remainingPerDayPaise = 0;
        }
      } catch (_) {
        // Ignored if invalid date
      }
    }

    return TripBudgetMeter(
      budgetPaise: budgetPaise,
      totalSpentPaise: totalSpentPaise,
      remainingPaise: remainingPaise,
      spentPercent: spentPercent,
      level: level,
      statusMessage: statusMessage,
      daysTotal: daysTotal,
      daysElapsed: daysElapsed,
      daysRemaining: daysRemaining,
      remainingPerDayPaise: remainingPerDayPaise,
      isOverBudget: totalSpentPaise > budgetPaise,
    );
  }

  Future<List<TripModel>> fetchTrips() async {
    await _ensureLoaded();
    return List.unmodifiable(_trips);
  }

  Future<TripModel> getTripById(String tripId) async {
    await _ensureLoaded();
    return _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => _trips.isNotEmpty
          ? _trips.first
          : TripModel(
              id: tripId,
              name: 'Trip',
              budgetPaise: 5000000,
              isCompleted: false,
              creatorUserId: 'usr_arhaam',
              isAdmin: true,
              membersCount: 1,
              myNetPaise: 0,
              totalSpentPaise: 0,
              createdAt: DateTime.now().toIso8601String(),
            ),
    );
  }

  Future<TripModel> createTrip({
    required String name,
    required int budgetPaise,
    String? startDate,
    String? endDate,
    required List<String> memberUserIds,
    String? sourceGroupId,
    String? photoUrl,
    String creatorUserId = 'usr_arhaam',
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));

    final tripId = 'trp_${DateTime.now().millisecondsSinceEpoch}';
    final Set<String> memberSet = {creatorUserId, ...memberUserIds};

    // If sourceGroupId passed, copy members snapshot (no live link)
    if (sourceGroupId != null) {
      final grp = MockDataRepository.groups.where((g) => g.id == sourceGroupId);
      if (grp.isNotEmpty) {
        for (final m in grp.first.members) {
          memberSet.add(m.id);
        }
      }
    }

    final membersList = memberSet.map((uid) {
      final isCreator = uid == creatorUserId;
      String mName = 'Member';
      String phone = '+919999900000';
      bool isAppUser = true;

      if (uid == MockDataRepository.currentUser.id) {
        mName = MockDataRepository.currentUser.name;
        phone = MockDataRepository.currentUser.phone;
      } else {
        final f = MockDataRepository.friends.where((fr) => fr.user.id == uid);
        if (f.isNotEmpty) {
          mName = f.first.user.name;
          phone = f.first.user.phone;
          isAppUser = !f.first.user.isPlaceholder;
        }
      }

      return TripMember(
        userId: uid,
        name: mName,
        phoneE164: phone,
        role: isCreator ? 'ADMIN' : 'MEMBER',
        netPaise: 0,
        isAppUser: isAppUser,
      );
    }).toList();

    final meter = computeBudgetMeter(budgetPaise, 0, startDate, endDate);

    final trip = TripModel(
      id: tripId,
      name: name,
      photoUrl: photoUrl,
      budgetPaise: budgetPaise,
      startDate: startDate,
      endDate: endDate,
      status: 'ACTIVE',
      isCompleted: false,
      creatorUserId: creatorUserId,
      isAdmin: true,
      membersCount: membersList.length,
      myNetPaise: 0,
      totalSpentPaise: 0,
      createdAt: DateTime.now().toIso8601String(),
      members: membersList,
      budgetMeter: meter,
    );

    _trips = [trip, ..._trips];
    await _saveToStorage();
    return trip;
  }

  Future<TripModel> updateTripBudget(
    String tripId,
    int newBudgetPaise, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 100));
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) throw Exception('Trip not found');

    final trip = _trips[index];
    if (trip.creatorUserId != actorUserId) {
      throw Exception('FORBIDDEN: Only trip creator can change budget');
    }

    final meter = computeBudgetMeter(
      newBudgetPaise,
      trip.totalSpentPaise,
      trip.startDate,
      trip.endDate,
    );

    final updated = trip.copyWith(
      budgetPaise: newBudgetPaise,
      budgetMeter: meter,
    );
    _trips[index] = updated;
    await _saveToStorage();
    return updated;
  }

  Future<TripModel> updateTrip(
    String tripId, {
    String? name,
    String? startDate,
    String? endDate,
    String? photoUrl,
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 100));
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) throw Exception('Trip not found');

    final trip = _trips[index];
    if (trip.creatorUserId != actorUserId) {
      throw Exception('FORBIDDEN: Only trip creator can edit trip details');
    }

    final meter = computeBudgetMeter(
      trip.budgetPaise,
      trip.totalSpentPaise,
      startDate ?? trip.startDate,
      endDate ?? trip.endDate,
    );

    final updated = trip.copyWith(
      name: name,
      startDate: startDate,
      endDate: endDate,
      photoUrl: photoUrl,
      budgetMeter: meter,
    );
    _trips[index] = updated;
    await _saveToStorage();
    return updated;
  }

  Future<TripModel> completeTrip(
    String tripId, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 100));
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) throw Exception('Trip not found');

    final trip = _trips[index];
    if (trip.creatorUserId != actorUserId) {
      throw Exception('FORBIDDEN: Only trip creator can complete trip');
    }

    final updated = trip.copyWith(
      status: 'COMPLETED',
      isCompleted: true,
    );
    _trips[index] = updated;
    await _saveToStorage();
    return updated;
  }

  Future<void> removeMember(
    String tripId,
    String targetUserId, {
    String actorUserId = 'usr_arhaam',
  }) async {
    await _ensureLoaded();
    await Future.delayed(const Duration(milliseconds: 100));
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) throw Exception('Trip not found');

    final trip = _trips[index];
    if (trip.creatorUserId != actorUserId && actorUserId != targetUserId) {
      throw Exception('FORBIDDEN: Only trip creator can remove members');
    }

    final targetMember = trip.members.firstWhere(
      (m) => m.userId == targetUserId,
      orElse: () => throw Exception('User is not a member of this trip'),
    );

    if (targetMember.netPaise != 0) {
      throw Exception('UNSETTLED_BALANCE: Cannot remove member with unsettled balance');
    }

    final updatedMembers = trip.members.where((m) => m.userId != targetUserId).toList();
    _trips[index] = trip.copyWith(
      members: updatedMembers,
    );
    await _saveToStorage();
  }

  TripDashboardData getDashboard(String tripId) {
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => _trips.first,
    );

    final meter = trip.budgetMeter ??
        computeBudgetMeter(
          trip.budgetPaise,
          trip.totalSpentPaise,
          trip.startDate,
          trip.endDate,
        );

    final categoryBreakdown = const [
      CategoryBreakdownItem(category: 'stay', totalPaise: 1800000, percentage: 47),
      CategoryBreakdownItem(category: 'food', totalPaise: 1240000, percentage: 32),
      CategoryBreakdownItem(category: 'travel', totalPaise: 500000, percentage: 13),
      CategoryBreakdownItem(category: 'other', totalPaise: 300000, percentage: 8),
    ];

    final dailySpending = const [
      TripDailySpendingItem(date: '2026-10-12', dayLabel: 'Day 1 (Oct 12)', totalPaise: 1500000),
      TripDailySpendingItem(date: '2026-10-13', dayLabel: 'Day 2 (Oct 13)', totalPaise: 840000),
      TripDailySpendingItem(date: '2026-10-14', dayLabel: 'Day 3 (Oct 14)', totalPaise: 1000000),
      TripDailySpendingItem(date: '2026-10-15', dayLabel: 'Day 4 (Oct 15)', totalPaise: 500000),
    ];

    final memberSpends = [
      TripMemberSpendItem(
        userId: 'usr_arhaam',
        name: 'Arhaam (You)',
        paidPaise: 2340000,
        sharePaise: 960000,
        netPaise: 1380000,
      ),
      TripMemberSpendItem(
        userId: 'usr_rahul',
        name: 'Rahul',
        paidPaise: 1000000,
        sharePaise: 960000,
        netPaise: 40000,
      ),
      TripMemberSpendItem(
        userId: 'usr_priya',
        name: 'Priya',
        paidPaise: 500000,
        sharePaise: 960000,
        netPaise: -460000,
      ),
      TripMemberSpendItem(
        userId: 'usr_sneha',
        name: 'Sneha',
        paidPaise: 0,
        sharePaise: 960000,
        netPaise: -960000,
      ),
    ];

    final expenses = [
      ExpenseModel(
        id: 'exp_resort',
        ledgerId: tripId,
        title: 'Beach Villa Resort (2 Nights)',
        totalPaise: 1800000,
        category: 'stay',
        splitType: 'EQUAL',
        expenseDate: '2026-10-12',
        createdBy: 'usr_arhaam',
        createdAt: DateTime.parse('2026-10-12T14:00:00Z'),
        updatedAt: DateTime.parse('2026-10-12T14:00:00Z'),
        payers: [const ExpensePayer(userId: 'usr_arhaam', paidPaise: 1800000)],
        splits: [
          const ExpenseSplit(userId: 'usr_arhaam', owedPaise: 450000, included: true),
          const ExpenseSplit(userId: 'usr_rahul', owedPaise: 450000, included: true),
          const ExpenseSplit(userId: 'usr_priya', owedPaise: 450000, included: true),
          const ExpenseSplit(userId: 'usr_sneha', owedPaise: 450000, included: true),
        ],
      ),
      ExpenseModel(
        id: 'exp_dinner',
        ledgerId: tripId,
        title: 'Seafood Shack Dinner',
        totalPaise: 840000,
        category: 'food',
        splitType: 'EQUAL',
        expenseDate: '2026-10-13',
        createdBy: 'usr_rahul',
        createdAt: DateTime.parse('2026-10-13T21:30:00Z'),
        updatedAt: DateTime.parse('2026-10-13T21:30:00Z'),
        payers: [const ExpensePayer(userId: 'usr_rahul', paidPaise: 840000)],
        splits: [
          const ExpenseSplit(userId: 'usr_arhaam', owedPaise: 210000, included: true),
          const ExpenseSplit(userId: 'usr_rahul', owedPaise: 210000, included: true),
          const ExpenseSplit(userId: 'usr_priya', owedPaise: 210000, included: true),
          const ExpenseSplit(userId: 'usr_sneha', owedPaise: 210000, included: true),
        ],
      ),
      ExpenseModel(
        id: 'exp_sports',
        ledgerId: tripId,
        title: 'Scuba Diving & Jet Ski',
        totalPaise: 1200000,
        category: 'other',
        splitType: 'EQUAL',
        expenseDate: '2026-10-14',
        createdBy: 'usr_arhaam',
        createdAt: DateTime.parse('2026-10-14T11:00:00Z'),
        updatedAt: DateTime.parse('2026-10-14T11:00:00Z'),
        payers: [const ExpensePayer(userId: 'usr_arhaam', paidPaise: 1200000)],
        splits: [
          const ExpenseSplit(userId: 'usr_arhaam', owedPaise: 300000, included: true),
          const ExpenseSplit(userId: 'usr_rahul', owedPaise: 300000, included: true),
          const ExpenseSplit(userId: 'usr_priya', owedPaise: 300000, included: true),
          const ExpenseSplit(userId: 'usr_sneha', owedPaise: 300000, included: true),
        ],
      ),
    ];

    return TripDashboardData(
      trip: trip,
      budgetMeter: meter,
      categoryBreakdown: categoryBreakdown,
      dailySpending: dailySpending,
      memberSpends: memberSpends,
      expenses: expenses,
    );
  }

  GroupGraphData getGraph(String tripId) {
    // Reuses graph visualization structure with ZERO offsets
    final nodes = [
      const GraphNode(userId: 'usr_arhaam', name: 'Arhaam (You)', netPaise: 1380000),
      const GraphNode(userId: 'usr_rahul', name: 'Rahul', netPaise: 40000),
      const GraphNode(userId: 'usr_priya', name: 'Priya', netPaise: -460000),
      const GraphNode(userId: 'usr_sneha', name: 'Sneha', netPaise: -960000),
    ];

    final links = [
      const GraphLink(fromUserId: 'usr_sneha', toUserId: 'usr_arhaam', amountPaise: 960000, isPending: false),
      const GraphLink(fromUserId: 'usr_priya', toUserId: 'usr_arhaam', amountPaise: 420000, isPending: false),
      const GraphLink(fromUserId: 'usr_priya', toUserId: 'usr_rahul', amountPaise: 40000, isPending: false),
    ];

    return GroupGraphData(
      groupId: tripId,
      mode: 'simplified',
      nodes: nodes,
      links: links,
    );
  }
}

final tripsRepositoryProvider = Provider<TripsRepository>((ref) {
  return TripsRepository();
});

class TripsNotifier extends AsyncNotifier<List<TripModel>> {
  @override
  Future<List<TripModel>> build() async {
    return ref.read(tripsRepositoryProvider).fetchTrips();
  }

  Future<void> createTrip({
    required String name,
    required int budgetPaise,
    String? startDate,
    String? endDate,
    required List<String> memberUserIds,
    String? sourceGroupId,
    String? photoUrl,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(tripsRepositoryProvider).createTrip(
            name: name,
            budgetPaise: budgetPaise,
            startDate: startDate,
            endDate: endDate,
            memberUserIds: memberUserIds,
            sourceGroupId: sourceGroupId,
            photoUrl: photoUrl,
          );
      return ref.read(tripsRepositoryProvider).fetchTrips();
    });
  }

  Future<void> updateTripBudget(String tripId, int newBudgetPaise) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(tripsRepositoryProvider).updateTripBudget(tripId, newBudgetPaise);
      return ref.read(tripsRepositoryProvider).fetchTrips();
    });
    ref.invalidate(tripDetailProvider(tripId));
    ref.invalidate(tripDashboardProvider(tripId));
  }

  Future<void> updateTrip(
    String tripId, {
    String? name,
    String? startDate,
    String? endDate,
    String? photoUrl,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(tripsRepositoryProvider).updateTrip(
            tripId,
            name: name,
            startDate: startDate,
            endDate: endDate,
            photoUrl: photoUrl,
          );
      return ref.read(tripsRepositoryProvider).fetchTrips();
    });
    ref.invalidate(tripDetailProvider(tripId));
    ref.invalidate(tripDashboardProvider(tripId));
  }

  Future<void> completeTrip(String tripId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(tripsRepositoryProvider).completeTrip(tripId);
      return ref.read(tripsRepositoryProvider).fetchTrips();
    });
    ref.invalidate(tripDetailProvider(tripId));
    ref.invalidate(tripDashboardProvider(tripId));
  }

  Future<void> removeMember(String tripId, String targetUserId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(tripsRepositoryProvider).removeMember(tripId, targetUserId);
      return ref.read(tripsRepositoryProvider).fetchTrips();
    });
    ref.invalidate(tripDetailProvider(tripId));
    ref.invalidate(tripDashboardProvider(tripId));
  }
}

final tripsNotifierProvider = AsyncNotifierProvider<TripsNotifier, List<TripModel>>(() {
  return TripsNotifier();
});

final tripDetailProvider = FutureProvider.family<TripModel, String>((ref, tripId) async {
  return ref.watch(tripsRepositoryProvider).getTripById(tripId);
});

final tripDashboardProvider = Provider.family<TripDashboardData, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).getDashboard(tripId);
});

final tripGraphProvider = Provider.family<GroupGraphData, String>((ref, tripId) {
  return ref.watch(tripsRepositoryProvider).getGraph(tripId);
});
