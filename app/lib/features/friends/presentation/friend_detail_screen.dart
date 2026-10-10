import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class FriendDetailScreen extends StatelessWidget {
  final String friendId;

  const FriendDetailScreen({super.key, required this.friendId});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final friend = MockDataRepository.friends.firstWhere(
      (f) => f.user.id == friendId,
      orElse: () => MockDataRepository.friends.first,
    );

    final expenses = MockDataRepository.expenses;
    final isOwe = friend.netPaise < 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          friend.user.displayName,
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        actions: [
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
              // Friend Header Hero Card
              GlassCard(
                strong: true,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Avatar(
                      name: friend.user.displayName,
                      size: 64,
                      isPlaceholder: friend.user.isPlaceholder,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      friend.user.displayName,
                      style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 20),
                    ),
                    Text(
                      friend.user.phone,
                      style: SplitUpTypography.label(color: colors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Container(height: 1, color: colors.divider),
                    const SizedBox(height: 16),
                    Text(
                      isOwe ? 'YOU OWE RAHUL' : (friend.netPaise > 0 ? 'RAHUL OWES YOU' : 'ALL SETTLED UP'),
                      style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    MoneyText(
                      friend.netPaise.abs(),
                      variant: MoneyVariant.title,
                      customColor: isOwe
                          ? colors.accentOwe
                          : (friend.netPaise > 0 ? colors.accentReceive : colors.textSecondary),
                    ),
                    if (isOwe) ...[
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: 'Settle ${formatPaise(friend.netPaise.abs())}',
                        icon: Icons.check_circle_outline,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: colors.surfaceFlatRaised,
                              content: Text(
                                'Settlement request sent to ${friend.user.displayName}!',
                                style: SplitUpTypography.body(color: colors.textPrimary),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),

              // "Also in" Groups section
              if (friend.commonGroups.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Also in groups',
                  style: SplitUpTypography.label(color: colors.textMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: friend.commonGroups.map((g) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.surfaceFlat,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_outlined, size: 14, color: colors.accentBrass),
                          const SizedBox(width: 6),
                          Text(
                            g,
                            style: SplitUpTypography.label(color: colors.textPrimary),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                'Shared Expenses & Activity',
                style: SplitUpTypography.title(color: colors.textPrimary),
              ),
              const SizedBox(height: 12),

              // Expense items
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
                            Text(
                              exp.title,
                              style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Paid by ${exp.paidBy.displayName}',
                              style: SplitUpTypography.caption(color: colors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                            exp.totalPaise,
                            variant: MoneyVariant.body,
                            colored: false,
                          ),
                          Text(
                            'Equal split',
                            style: SplitUpTypography.caption(color: colors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
