import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../../core/auth/auth_provider.dart';
import '../data/trips_repository.dart';
import '../domain/trip_model.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../expenses/presentation/add_expense_screen.dart';
import '../../expenses/presentation/expense_detail_sheet.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../expenses/domain/expense_model.dart';
import '../../settlements/presentation/settle_sheet.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final _budgetController = TextEditingController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTripData();
    });

    // Rule R9: 15-second poll while trip page is open
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _syncTripData();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncTripData();
    }
  }

  Future<void> _syncTripData() async {
    try {
      ref.invalidate(tripDetailProvider(widget.tripId));
      ref.invalidate(tripDashboardProvider(widget.tripId));
      await ref.read(expensesNotifierProvider.notifier).syncExpensesForLedger(widget.tripId);
    } catch (_) {}
  }

  Color _getMeterColor(double spentPercent, SplitUpColors colors) {
    if (spentPercent < 60) {
      return colors.accentReceive; // Green
    } else if (spentPercent < 80) {
      return colors.statusWarn; // Amber
    } else if (spentPercent <= 100) {
      return const Color(0xFFF97316); // Orange warning
    } else {
      return colors.accentOwe; // Red over-budget
    }
  }

  void _showEditBudgetDialog(TripModel trip) {
    _budgetController.text = (trip.budgetPaise ~/ 100).toString();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ctx.colors.surfaceFlat,
          title: Text(
            'Update Trip Budget',
            style: SplitUpTypography.title(color: ctx.colors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Only the trip creator can adjust the budget.',
                style: SplitUpTypography.caption(color: ctx.colors.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                style: SplitUpTypography.titleAmount(color: ctx.colors.textPrimary),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: SplitUpTypography.label(color: ctx.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ctx.colors.accentReceive),
              onPressed: () async {
                final rupees = int.tryParse(_budgetController.text.trim()) ?? 0;
                if (rupees > 0) {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(tripsNotifierProvider.notifier)
                      .updateTripBudget(widget.tripId, rupees * 100);
                  ref.invalidate(tripDetailProvider(widget.tripId));
                  ref.invalidate(tripDashboardProvider(widget.tripId));
                }
              },
              child: const Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(TripModel trip) {
    final nameController = TextEditingController(text: trip.name);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: ctx.colors.surfaceFlat,
          title: Text('Rename Trip', style: SplitUpTypography.title(color: ctx.colors.textPrimary)),
          content: TextField(
            controller: nameController,
            style: SplitUpTypography.body(color: ctx.colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Trip name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: SplitUpTypography.label(color: ctx.colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ctx.colors.accentReceive),
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  await ref
                      .read(tripsNotifierProvider.notifier)
                      .updateTrip(widget.tripId, name: newName);
                  ref.invalidate(tripDetailProvider(widget.tripId));
                  ref.invalidate(tripDashboardProvider(widget.tripId));
                }
              },
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _completeTrip(TripModel trip) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surfaceFlat,
        title: Text('Mark Trip as Completed?', style: SplitUpTypography.title(color: ctx.colors.textPrimary)),
        content: Text(
          'Completed trips move to the Completed tab. You and trip members can still add settlements and view all records.',
          style: SplitUpTypography.body(color: ctx.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: SplitUpTypography.label(color: ctx.colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ctx.colors.accentReceive),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Complete Trip', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(tripsNotifierProvider.notifier).completeTrip(widget.tripId);
      ref.invalidate(tripDetailProvider(widget.tripId));
      ref.invalidate(tripDashboardProvider(widget.tripId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip marked as completed.')),
        );
      }
    }
  }

  void _showMembersSheet(TripModel trip) {
    final currentUserId = (ref.read(authNotifierProvider).user?.id?.isNotEmpty ?? false) ? ref.read(authNotifierProvider).user!.id : 'usr_arhaam';
    final members = trip.members.map((m) {
      return MemberDisplayInfo(
        userId: m.userId,
        name: m.name,
        phoneE164: m.phoneE164,
        photoUrl: m.photoUrl,
        role: m.role,
        netPaise: m.netPaise,
        isAppUser: m.isAppUser,
        isMe: m.userId == currentUserId,
      );
    }).toList();

    MembersSheet.show(
      context: context,
      title: 'Trip Members',
      entityName: trip.name,
      members: members,
      onRemoveMember: trip.isAdmin
          ? (member) async {
              await ref
                  .read(tripsNotifierProvider.notifier)
                  .removeMember(trip.id, member.userId);
              ref.invalidate(tripDetailProvider(widget.tripId));
              ref.invalidate(tripDashboardProvider(widget.tripId));
            }
          : null,
      onRemindToSettle: (member) async {
        final notif = NotificationModel(
          id: 'notif_remind_${DateTime.now().millisecondsSinceEpoch}',
          type: 'SETTLEMENT_REQUESTED',
          title: 'Settlement Reminder: ${trip.name}',
          body: '${member.name}, please settle your pending balance of ${formatPaise(member.netPaise.abs())} in ${trip.name}.',
          isRead: false,
          createdAt: DateTime.now(),
          payload: {
            'tripId': trip.id,
            'tripName': trip.name,
            'userId': member.userId,
            'userName': member.name,
            'netPaise': member.netPaise,
          },
        );
        await ref.read(notificationsNotifierProvider.notifier).addNotification(notif);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: context.colors.accentReceive,
              content: Text(
                'Settlement reminder notification sent to ${member.name} (${formatPaise(member.netPaise.abs())})',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncTrip = ref.watch(tripDetailProvider(widget.tripId));
    final dashboardData = ref.watch(tripDashboardProvider(widget.tripId));

    return asyncTrip.when(
      loading: () => const SplitUpLoadingView(message: 'Loading trip details...'),
      error: (e, _) {
        final cachedTrips = ref.watch(tripsNotifierProvider).maybeWhen(
              data: (list) => list,
              orElse: () => <TripModel>[],
            );
        final cachedTrip = cachedTrips.where((t) => t.id == widget.tripId).firstOrNull;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
              onPressed: () => context.pop(),
            ),
            title: Text(cachedTrip?.name ?? 'Trip', style: SplitUpTypography.title(color: colors.textPrimary)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Retry',
                onPressed: () => ref.invalidate(tripDetailProvider(widget.tripId)),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: colors.accentOwe.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 18, color: colors.accentOwe),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cachedTrip != null
                            ? 'Offline mode: displaying cached trip data.'
                            : 'Could not load trip details.',
                        style: SplitUpTypography.caption(color: colors.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(tripDetailProvider(widget.tripId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: cachedTrip != null
                    ? ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surfaceFlat,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cachedTrip.name, style: SplitUpTypography.title(color: colors.textPrimary)),
                                const SizedBox(height: 8),
                                Text('Budget: ${formatPaise(cachedTrip.budgetPaise)}',
                                    style: SplitUpTypography.body(color: colors.textSecondary)),
                                const SizedBox(height: 4),
                                Text('Total Spent: ${formatPaise(cachedTrip.totalSpentPaise)}',
                                    style: SplitUpTypography.body(color: colors.textSecondary)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text('Members (${cachedTrip.membersCount})',
                              style: SplitUpTypography.title(color: colors.textPrimary)),
                          const SizedBox(height: 12),
                          ...cachedTrip.members.map((m) => ListTile(
                                dense: true,
                                title: Text(m.name, style: TextStyle(color: colors.textPrimary)),
                                subtitle: Text(m.role, style: TextStyle(color: colors.textMuted)),
                                trailing: MoneyText(m.netPaise, variant: MoneyVariant.body),
                              )),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Error: $e', style: TextStyle(color: colors.accentOwe)),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => ref.invalidate(tripDetailProvider(widget.tripId)),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
      data: (trip) {
        final meter = trip.budgetMeter ??
            TripsRepository.computeBudgetMeter(
              trip.budgetPaise,
              trip.totalSpentPaise,
              trip.startDate,
              trip.endDate,
            );
        final pct = meter.spentPercent.toStringAsFixed(1);
        final meterColor = _getMeterColor(meter.spentPercent, colors);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
              onPressed: () => context.pop(),
            ),
            title: Text(
              trip.name,
              style: SplitUpTypography.title(color: colors.textPrimary),
            ),
            actions: [
              if (trip.isAdmin)
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: colors.textPrimary),
                  tooltip: 'Rename Trip',
                  onPressed: () => _showRenameDialog(trip),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: colors.textPrimary),
                color: colors.surfaceFlatRaised,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'view_members') {
                    _showMembersSheet(trip);
                  } else if (val == 'settle_graph') {
                    context.push('/trips/${trip.id}/graph');
                  } else if (val == 'budget') {
                    _showEditBudgetDialog(trip);
                  } else if (val == 'complete') {
                    _completeTrip(trip);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'view_members',
                    child: Row(
                      children: [
                        Icon(Icons.people_alt_outlined, size: 18, color: colors.textPrimary),
                        const SizedBox(width: 10),
                        Text('View Members', style: TextStyle(color: colors.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'settle_graph',
                    child: Row(
                      children: [
                        Icon(Icons.hub_outlined, size: 18, color: colors.textPrimary),
                        const SizedBox(width: 10),
                        Text('Settlement Graph', style: TextStyle(color: colors.textPrimary)),
                      ],
                    ),
                  ),
                  if (trip.isAdmin) ...[
                    PopupMenuItem(
                      value: 'budget',
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 18, color: colors.textPrimary),
                          const SizedBox(width: 10),
                          Text('Adjust Budget', style: TextStyle(color: colors.textPrimary)),
                        ],
                      ),
                    ),
                    if (!trip.isCompleted)
                      PopupMenuItem(
                        value: 'complete',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 18, color: colors.textPrimary),
                            const SizedBox(width: 10),
                            Text('Mark Completed', style: TextStyle(color: colors.textPrimary)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: colors.accentReceive,
              labelColor: colors.accentReceive,
              unselectedLabelColor: colors.textMuted,
              labelStyle: SplitUpTypography.label(color: colors.accentReceive),
              tabs: const [
                Tab(text: 'Dashboard'),
                Tab(text: 'Expenses'),
                Tab(text: 'Settle'),
              ],
            ),
          ),
          body: AppBackground(
            child: SafeArea(
              bottom: false,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Dashboard
                  _buildDashboardTab(trip, meter, meterColor, pct, colors, dashboardData),

                  // Tab 2: Expenses
                  _buildExpensesTab(trip, colors, dashboardData),

                  // Tab 3: Settle & Graph (Isolated without offsets)
                  _buildSettleTab(trip, colors),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: colors.accentReceive,
            foregroundColor: Colors.white,
            onPressed: () {
              final currentUserId = (ref.read(authNotifierProvider).user?.id?.isNotEmpty ?? false) ? ref.read(authNotifierProvider).user!.id : 'usr_arhaam';
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => AddExpenseScreen(
                    initialLedgerId: trip.id,
                    initialMembers: trip.members.map((m) {
                      final isMe = m.userId == currentUserId;
                      return {
                        'id': m.userId,
                        'name': isMe ? 'You' : m.name,
                        'isMe': isMe,
                      };
                    }).toList(),
                  ),
                ),
              );
            },
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        );
      },
    );
  }

  Widget _buildDashboardTab(
    TripModel trip,
    TripBudgetMeter meter,
    Color meterColor,
    String pct,
    SplitUpColors colors,
    TripDashboardData dashboard,
  ) {
    final double progressClamped = (meter.spentPercent / 100).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Trip Dates & Status
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: colors.accentBrass),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trip.startDate != null && trip.endDate != null
                          ? '${trip.startDate} – ${trip.endDate}'
                          : 'Time-boxed Trip Ledger',
                      style: SplitUpTypography.label(color: colors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(status: trip.isCompleted ? 'COMPLETED' : 'ACTIVE'),
          ],
        ),
        const SizedBox(height: 16),

        // Budget Gauge Hero Card
        GlassCard(
          strong: true,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TRIP BUDGET GAUGE',
                    style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: meterColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$pct%',
                      style: SplitUpTypography.caption(color: meterColor).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  MoneyText(meter.totalSpentPaise, variant: MoneyVariant.title, colored: false),
                  Text(
                    ' / ${formatPaise(meter.budgetPaise)}',
                    style: SplitUpTypography.title(color: colors.textMuted).copyWith(fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progressClamped,
                  backgroundColor: colors.surfaceFlatRaised,
                  color: meterColor,
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 14),

              // Status message & Remaining
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      meter.statusMessage,
                      style: SplitUpTypography.body(color: meterColor).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    meter.remainingPaise >= 0
                        ? 'Left: ${formatPaise(meter.remainingPaise)}'
                        : 'Over: ${formatPaise(-meter.remainingPaise)}',
                    style: SplitUpTypography.label(color: colors.textPrimary),
                  ),
                ],
              ),

              // Remaining per day (when dates exist)
              if (meter.remainingPerDayPaise != null && meter.daysRemaining != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.surfaceFlatRaised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.trending_up_rounded, size: 16, color: colors.accentBrass),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: 'Per day: ',
                                style: SplitUpTypography.caption(color: colors.textMuted),
                              ),
                              TextSpan(
                                text: '${formatPaise(meter.remainingPerDayPaise!)}/day',
                                style: SplitUpTypography.caption(color: colors.textPrimary).copyWith(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${meter.daysRemaining}d left',
                        style: SplitUpTypography.caption(color: colors.accentBrass),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Budget Slider (Creator only)
        if (trip.isAdmin) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Adjust Budget (Creator Only)',
                        style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _showEditBudgetDialog(trip),
                      child: Text('Edit Amount', style: SplitUpTypography.label(color: colors.accentReceive)),
                    ),
                  ],
                ),
                Slider(
                  value: (trip.budgetPaise ~/ 100).toDouble().clamp(10000.0, 150000.0),
                  min: 10000.0,
                  max: 150000.0,
                  divisions: 28,
                  label: '₹ ${(trip.budgetPaise ~/ 100)}',
                  activeColor: colors.accentReceive,
                  inactiveColor: colors.surfaceFlatRaised,
                  onChanged: (val) {
                    ref.read(tripsNotifierProvider.notifier).updateTripBudget(trip.id, val.toInt() * 100);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Daily Spending Bars
        if (dashboard.dailySpending.isNotEmpty) ...[
          Text('Daily Spending', style: SplitUpTypography.title(color: colors.textPrimary)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: dashboard.dailySpending.map((day) {
                final double barWidthRatio = (day.totalPaise / 2000000).clamp(0.05, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          day.dayLabel,
                          style: SplitUpTypography.caption(color: colors.textMuted),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: barWidthRatio,
                            backgroundColor: colors.surfaceFlatRaised,
                            color: colors.accentReceive,
                            minHeight: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatPaise(day.totalPaise),
                        style: SplitUpTypography.label(color: colors.textPrimary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Category Breakdown
        Text('Category Breakdown', style: SplitUpTypography.title(color: colors.textPrimary)),
        const SizedBox(height: 10),
        if (dashboard.categoryBreakdown.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: [
                Icon(Icons.pie_chart_outline_rounded, size: 40, color: colors.textMuted),
                const SizedBox(height: 10),
                Text('No category data yet', style: SplitUpTypography.title(color: colors.textPrimary)),
                const SizedBox(height: 4),
                Text('Add expenses to see category breakdown', style: SplitUpTypography.caption(color: colors.textMuted)),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: dashboard.categoryBreakdown.map((cat) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(
                        cat.category == 'food'
                            ? Icons.restaurant_rounded
                            : (cat.category == 'stay'
                                ? Icons.hotel_rounded
                                : (cat.category == 'travel' ? Icons.directions_car_rounded : Icons.receipt_long_rounded)),
                        size: 20,
                        color: colors.accentBrass,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cat.category.toUpperCase(),
                          style: SplitUpTypography.label(color: colors.textPrimary),
                        ),
                      ),
                      Text(
                        '${cat.percentage}% · ${formatPaise(cat.totalPaise)}',
                        style: SplitUpTypography.caption(color: colors.textSecondary),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 24),

        if (trip.isAdmin && !trip.isCompleted) ...[
          SecondaryButton(
            label: 'Mark Trip as Completed',
            icon: Icons.check_circle_outline,
            onPressed: () => _completeTrip(trip),
          ),
          const SizedBox(height: 80),
        ],
      ],
    );
  }

  Widget _buildExpensesTab(TripModel trip, SplitUpColors colors, TripDashboardData dashboard) {
    final asyncExpenses = ref.watch(expensesNotifierProvider);
    final allExpenses = asyncExpenses.maybeWhen(
      data: (list) {
        final tripExpenses = list.where((e) => e.ledgerId == trip.id && e.deletedAt == null).toList();
        if (tripExpenses.isEmpty && trip.id == 'trp_goa_2026') {
          return dashboard.expenses;
        }
        return tripExpenses;
      },
      orElse: () => trip.id == 'trp_goa_2026' ? dashboard.expenses : <ExpenseModel>[],
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Trip Expenses (${allExpenses.length})', style: SplitUpTypography.title(color: colors.textPrimary)),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => AddExpenseScreen(
                      initialLedgerId: trip.id,
                      initialMembers: trip.members.map((m) {
                        final isMe = m.userId == 'usr_arhaam';
                        return {
                          'id': m.userId,
                          'name': isMe ? 'You' : m.name,
                          'isMe': isMe,
                        };
                      }).toList(),
                    ),
                  ),
                );
              },
              icon: Icon(Icons.add, size: 16, color: colors.accentReceive),
              label: Text('Add', style: SplitUpTypography.label(color: colors.accentReceive)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        ...allExpenses.map((exp) {
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => ExpenseDetailSheet.show(context, exp),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceFlat,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surfaceFlatRaised,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      exp.category == 'food'
                          ? Icons.restaurant_rounded
                          : (exp.category == 'travel' ? Icons.directions_car_rounded : Icons.receipt_long_rounded),
                      size: 20,
                      color: colors.accentBrass,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(exp.title, style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15)),
                        const SizedBox(height: 2),
                        Text('Paid by ${exp.payers.first.userId}', style: SplitUpTypography.caption(color: colors.textMuted)),
                      ],
                    ),
                  ),
                  MoneyText(exp.totalPaise, variant: MoneyVariant.body, colored: false),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSettleTab(TripModel trip, SplitUpColors colors) {
    final graph = ref.watch(tripGraphProvider((tripId: trip.id, simplified: true)));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Isolation Notice Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.accentBrass.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.accentBrass.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_clock_rounded, size: 20, color: colors.accentBrass),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Trip Ledgers are fully isolated. No offsets or cross-group balances apply.',
                  style: SplitUpTypography.caption(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Settle Graph CTA Card
        GlassCard(
          strong: true,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.hub_rounded, size: 48, color: colors.accentBrass),
              const SizedBox(height: 12),
              Text(
                'Settlement Node Graph',
                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'View visual diagram showing who pays whom on this trip with simplified or pairwise debts.',
                textAlign: TextAlign.center,
                style: SplitUpTypography.body(color: colors.textMuted).copyWith(fontSize: 13),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Open Settlement Graph',
                icon: Icons.hub_outlined,
                onPressed: () => context.push('/trips/${trip.id}/graph'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Direct Settlement Options', style: SplitUpTypography.title(color: colors.textPrimary)),
        const SizedBox(height: 12),

        // Transfers List
        if (graph.links.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surfaceFlat,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 40, color: colors.accentReceive),
                const SizedBox(height: 10),
                Text('All settled up!', style: SplitUpTypography.title(color: colors.textPrimary)),
                const SizedBox(height: 4),
                Text('No one owes anything on this trip.', style: SplitUpTypography.caption(color: colors.textMuted)),
              ],
            ),
          )
        else
          ...graph.links.map((link) {
            final fromMember = trip.members.firstWhere(
              (m) => m.userId == link.fromUserId,
              orElse: () => TripMember(userId: link.fromUserId, name: link.fromUserId, phoneE164: '', role: 'MEMBER', netPaise: 0, isAppUser: true),
            );
            final toMember = trip.members.firstWhere(
              (m) => m.userId == link.toUserId,
              orElse: () => TripMember(userId: link.toUserId, name: link.toUserId, phoneE164: '', role: 'MEMBER', netPaise: 0, isAppUser: true),
            );
            final currentUserId = (ref.watch(authNotifierProvider).user?.id?.isNotEmpty ?? false) ? ref.watch(authNotifierProvider).user!.id : 'usr_arhaam';
            final fromName = link.fromUserId == currentUserId ? 'You' : fromMember.name;
            final toName = link.toUserId == currentUserId ? 'You' : toMember.name;
            final isUserPaying = link.fromUserId == currentUserId;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceFlat,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                children: [
                  Avatar(name: isUserPaying ? toName : fromName, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUserPaying
                              ? 'Pay $toName'
                              : (link.toUserId == currentUserId
                                  ? '$fromName owes you'
                                  : '$fromName owes $toName'),
                          style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                        ),
                        Text(
                          'Trip debt: ${formatPaise(link.amountPaise)}',
                          style: SplitUpTypography.caption(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (isUserPaying)
                    SettleButton(
                      amountPaise: link.amountPaise,
                      compact: true,
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (ctx) => SettleSheet(
                            friendId: link.toUserId,
                            friendName: toName,
                            ledgerId: trip.id,
                            amountPaise: link.amountPaise,
                          ),
                        );
                      },
                    )
                  else
                    MoneyText(link.amountPaise, variant: MoneyVariant.body, colored: false),
                ],
              ),
            );
          }),
        const SizedBox(height: 80),
      ],
    );
  }
}
