import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class MergeExplainerScreen extends StatelessWidget {
  final int expenseCount;
  final int totalPaise;
  final String inviterName;

  const MergeExplainerScreen({
    super.key,
    this.expenseCount = 3,
    this.totalPaise = 185000,
    this.inviterName = 'Your friends',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),

                // Merge icon badge
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: colors.accentReceive.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.accentReceive, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.sync_alt_rounded,
                      size: 44,
                      color: colors.accentReceive,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  'Welcome to SplitUp!',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.headline(color: colors.textPrimary).copyWith(
                    fontSize: 28,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '$inviterName already added you to expenses before you joined.',
                  textAlign: TextAlign.center,
                  style: SplitUpTypography.body(color: colors.textSecondary).copyWith(
                    fontSize: 16,
                  ),
                ),

                const Spacer(flex: 2),

                // Merge summary glass card
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Shared Expenses Linked',
                            style: SplitUpTypography.body(color: colors.textSecondary),
                          ),
                          Text(
                            '$expenseCount expenses',
                            style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 16),
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Amount Logged',
                            style: SplitUpTypography.body(color: colors.textSecondary),
                          ),
                          MoneyText(
                            totalPaise,
                            variant: MoneyVariant.title,
                            customColor: colors.accentReceive,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'All past history is now safely attached to your verified phone number.',
                        textAlign: TextAlign.center,
                        style: SplitUpTypography.caption(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 3),

                PrimaryButton(
                  label: 'Continue to SplitUp',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => context.go('/home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
