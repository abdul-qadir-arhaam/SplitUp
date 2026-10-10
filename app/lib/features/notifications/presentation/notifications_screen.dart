import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final notifs = MockDataRepository.notifications;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Notifications',
          style: SplitUpTypography.title(color: colors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: Text(
              'Mark all read',
              style: SplitUpTypography.label(color: colors.accentBrass),
            ),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            itemCount: notifs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final n = notifs[index];
              final hasAction = n.actionState == 'OPEN';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: n.isRead ? colors.surfaceFlat : colors.glassFillStrong,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: n.isRead ? colors.divider : colors.accentReceive.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.surfaceFlatRaised,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            n.type.contains('SETTLEMENT')
                                ? Icons.verified_user_outlined
                                : (n.type.contains('BUDGET') ? Icons.warning_amber_rounded : Icons.person_add_outlined),
                            size: 18,
                            color: n.type.contains('BUDGET') ? colors.statusWarn : colors.accentReceive,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title,
                                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                n.message,
                                style: SplitUpTypography.body(color: colors.textSecondary).copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Inline Action buttons if actionable settlement
                    if (hasAction && n.relatedSettlement != null) ...[
                      const SizedBox(height: 14),
                      Container(height: 1, color: colors.divider),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              height: 42,
                              label: 'Confirm ${formatPaise(n.relatedSettlement!.amountPaise)}',
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: colors.surfaceFlatRaised,
                                    content: Text(
                                      'Settlement confirmed! Balances updated.',
                                      style: SplitUpTypography.body(color: colors.textPrimary),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SecondaryButton(
                              height: 42,
                              label: 'Reject',
                              textColor: colors.accentOwe,
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: colors.surfaceFlatRaised,
                                    content: Text(
                                      'Settlement rejected.',
                                      style: SplitUpTypography.body(color: colors.textPrimary),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
