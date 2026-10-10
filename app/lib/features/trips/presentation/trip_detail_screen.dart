import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class TripDetailScreen extends StatelessWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trip = MockDataRepository.trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => MockDataRepository.trips.first,
    );

    final expenses = MockDataRepository.expenses;
    final pct = (trip.budgetProgress * 100).toStringAsFixed(1);
    final remainingPaise = trip.budgetPaise - trip.spentPaise;

    Color meterColor;
    String statusMessage;
    if (trip.budgetProgress < 0.6) {
      meterColor = colors.accentReceive;
      statusMessage = 'Well within budget! Spending is healthy.';
    } else if (trip.budgetProgress < 0.8) {
      meterColor = colors.statusWarn;
      statusMessage = 'Caution: You have spent 76.8% of the trip budget.';
    } else if (trip.budgetProgress < 1.0) {
      meterColor = colors.statusWarn;
      statusMessage = 'Approaching budget limit! Keep an eye on expenses.';
    } else {
      meterColor = colors.accentOwe;
      statusMessage = 'Budget exceeded!';
    }

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
          IconButton(
            icon: Icon(Icons.share_outlined, color: colors.textPrimary),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: colors.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              // Trip Dates & Members Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 14, color: colors.accentBrass),
                      const SizedBox(width: 6),
                      Text(
                        'Oct 12 – Oct 16, 2026',
                        style: SplitUpTypography.label(color: colors.textSecondary),
                      ),
                    ],
                  ),
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
                        MoneyText(trip.spentPaise, variant: MoneyVariant.title, colored: false),
                        Text(
                          ' / ${formatPaise(trip.budgetPaise)}',
                          style: SplitUpTypography.title(color: colors.textMuted).copyWith(fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: trip.budgetProgress.clamp(0.0, 1.0),
                        backgroundColor: colors.surfaceFlatRaised,
                        color: meterColor,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Status Message and Remaining
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            statusMessage,
                            style: SplitUpTypography.caption(color: meterColor),
                          ),
                        ),
                        Text(
                          'Remaining: ${formatPaise(remainingPaise)}',
                          style: SplitUpTypography.label(color: colors.textPrimary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Trip Expenses
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Trip Expenses (${expenses.length})',
                    style: SplitUpTypography.title(color: colors.textPrimary),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push('/add-expense'),
                    icon: Icon(Icons.add, size: 16, color: colors.accentReceive),
                    label: Text(
                      'Add',
                      style: SplitUpTypography.label(color: colors.accentReceive),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ...expenses.map((exp) {
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
                            Text('Paid by ${exp.paidBy.displayName}', style: SplitUpTypography.caption(color: colors.textMuted)),
                          ],
                        ),
                      ),
                      MoneyText(exp.totalPaise, variant: MoneyVariant.body, colored: false),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 20),
              SecondaryButton(
                label: trip.isCompleted ? 'Reopen Trip' : 'Mark Trip as Completed',
                icon: Icons.check_circle_outline,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colors.surfaceFlatRaised,
                      content: Text(
                        'Trip marked as completed.',
                        style: SplitUpTypography.body(color: colors.textPrimary),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        onPressed: () => context.push('/add-expense'),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}
