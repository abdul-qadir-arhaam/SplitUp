import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/trips_repository.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  bool _showCompleted = false;

  Color _getMeterColor(double spentPercent, SplitUpColors colors) {
    if (spentPercent < 60) {
      return colors.accentReceive;
    } else if (spentPercent < 80) {
      return colors.statusWarn;
    } else if (spentPercent <= 100) {
      return const Color(0xFFF97316); // Orange warning
    } else {
      return colors.accentOwe; // Red exceeded
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final asyncTrips = ref.watch(tripsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Trips',
          style: SplitUpTypography.headline(color: colors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add_rounded, color: colors.accentReceive, size: 26),
            tooltip: 'Create Trip',
            onPressed: () => context.push('/trips/create'),
          ),
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: colors.textPrimary, size: 24),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: asyncTrips.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                'Error loading trips: $err',
                style: SplitUpTypography.body(color: colors.accentOwe),
              ),
            ),
            data: (allTrips) {
              final trips = allTrips.where((t) => t.isCompleted == _showCompleted).toList();

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // Active / Completed Segments
                  SegmentedControl<bool>(
                    values: const [false, true],
                    labels: const ['Active Trips', 'Completed Trips'],
                    selected: _showCompleted,
                    onSelected: (val) => setState(() => _showCompleted = val),
                  ),
                  const SizedBox(height: 16),

                  if (trips.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _showCompleted ? Icons.task_alt_rounded : Icons.flight_takeoff_rounded,
                            size: 48,
                            color: colors.textMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _showCompleted ? 'No completed trips yet' : 'No active trips',
                            style: SplitUpTypography.title(color: colors.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _showCompleted
                              ? 'Trips you mark as completed will appear here.'
                              : 'Create a time-boxed trip ledger with a custom budget.',
                            textAlign: TextAlign.center,
                            style: SplitUpTypography.caption(color: colors.textMuted),
                          ),
                          if (!_showCompleted) ...[
                            const SizedBox(height: 16),
                            PrimaryButton(
                              label: 'Create Trip',
                              icon: Icons.add,
                              onPressed: () => context.push('/trips/create'),
                            ),
                          ],
                        ],
                      ),
                    ),

                  ...trips.map((trip) {
                    final meter = trip.budgetMeter ??
                        TripsRepository.computeBudgetMeter(
                          trip.budgetPaise,
                          trip.totalSpentPaise,
                          trip.startDate,
                          trip.endDate,
                        );
                    final pct = meter.spentPercent.toStringAsFixed(1);
                    final meterColor = _getMeterColor(meter.spentPercent, colors);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: colors.divider),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => context.push('/trips/${trip.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      trip.name,
                                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  StatusChip(status: trip.isCompleted ? 'COMPLETED' : 'ACTIVE'),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Budget: ${formatPaise(trip.budgetPaise)} · Spent: ${formatPaise(trip.totalSpentPaise)} ($pct%)',
                                style: SplitUpTypography.caption(color: colors.textSecondary),
                              ),
                              const SizedBox(height: 14),

                              // Budget meter bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: (meter.spentPercent / 100).clamp(0.0, 1.0),
                                  backgroundColor: colors.surfaceFlatRaised,
                                  color: meterColor,
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Status message label
                              Text(
                                meter.statusMessage,
                                style: SplitUpTypography.caption(color: meterColor).copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 14),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      for (int i = 0; i < trip.members.length.clamp(0, 3); i++) ...[
                                        Align(
                                          widthFactor: 0.75,
                                          child: Avatar(name: trip.members[i].name, size: 28),
                                        ),
                                      ],
                                      if (trip.members.length > 3)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 10),
                                          child: Text(
                                            '+${trip.members.length - 3}',
                                            style: SplitUpTypography.caption(color: colors.textMuted),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        'View Dashboard',
                                        style: SplitUpTypography.label(color: colors.accentReceive),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.arrow_forward_ios_rounded, size: 12, color: colors.accentReceive),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 100),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        tooltip: 'Create New Trip',
        onPressed: () => context.push('/trips/create'),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}
