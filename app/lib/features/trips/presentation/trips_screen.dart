import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final allTrips = MockDataRepository.trips;
    final trips = allTrips.where((t) => t.isCompleted == _showCompleted).toList();

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
            icon: Icon(Icons.notifications_outlined, color: colors.textPrimary, size: 24),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
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

              ...trips.map((trip) {
                final pct = (trip.budgetProgress * 100).toStringAsFixed(0);
                Color meterColor;
                if (trip.budgetProgress < 0.6) {
                  meterColor = colors.accentReceive;
                } else if (trip.budgetProgress < 0.8) {
                  meterColor = colors.statusWarn;
                } else {
                  meterColor = colors.accentOwe;
                }

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
                              Text(
                                trip.name,
                                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 18),
                              ),
                              StatusChip(status: trip.isCompleted ? 'COMPLETED' : 'ACTIVE'),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Budget: ${formatPaise(trip.budgetPaise)} · Spent: ${formatPaise(trip.spentPaise)} ($pct%)',
                            style: SplitUpTypography.caption(color: colors.textSecondary),
                          ),
                          const SizedBox(height: 14),

                          // Budget meter bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: trip.budgetProgress.clamp(0.0, 1.0),
                              backgroundColor: colors.surfaceFlatRaised,
                              color: meterColor,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  for (int i = 0; i < trip.members.length.clamp(0, 3); i++) ...[
                                    Align(
                                      widthFactor: 0.75,
                                      child: Avatar(name: trip.members[i].displayName, size: 28),
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
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => context.push('/trips/create'),
        icon: const Icon(Icons.flight_takeoff_rounded, size: 22),
        label: Text(
          'Create Trip',
          style: SplitUpTypography.title(color: Colors.white).copyWith(fontSize: 15),
        ),
      ),
    );
  }
}
