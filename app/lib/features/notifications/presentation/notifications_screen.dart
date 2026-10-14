import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/notifications_repository.dart';
import '../../settlements/data/settlements_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  String _groupKey(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final difference = today.difference(itemDate).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final asyncNotifs = ref.watch(notificationsNotifierProvider);

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
          if (asyncNotifs.asData?.value.isNotEmpty ?? false) ...[
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: colors.surfaceFlatRaised,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: Text('Clear All Notifications', style: SplitUpTypography.title(color: colors.textPrimary)),
                    content: Text(
                      'Are you sure you want to clear all notifications?',
                      style: SplitUpTypography.body(color: colors.textSecondary),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text('Clear All', style: TextStyle(color: colors.accentOwe, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  ref.read(notificationsNotifierProvider.notifier).clearAll();
                }
              },
              child: Text(
                'Clear all',
                style: SplitUpTypography.label(color: colors.accentOwe),
              ),
            ),
          ],
          TextButton(
            onPressed: () => ref.read(notificationsNotifierProvider.notifier).markAllRead(),
            child: Text(
              'Mark all read',
              style: SplitUpTypography.label(color: colors.accentBrass),
            ),
          ),
        ],
      ),
      body: AppBackground(
        child: SafeArea(
          child: asyncNotifs.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: SplitUpLoadingAnimation(message: 'Loading notifications...'),
              ),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'No notifications',
                    message: "You're all caught up!",
                  ),
                );
              }

              // Group items
              final grouped = <String, List<NotificationModel>>{};
              for (final item in items) {
                final key = _groupKey(item.createdAt);
                grouped.putIfAbsent(key, () => []).add(item);
              }

              final groupKeys = ['Today', 'Yesterday', 'Earlier'].where((k) => grouped.containsKey(k)).toList();

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: groupKeys.length,
                itemBuilder: (context, gIndex) {
                  final groupTitle = groupKeys[gIndex];
                  final groupItems = grouped[groupTitle]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          groupTitle,
                          style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...groupItems.map((n) {
                        final isActionable = n.type == 'SETTLEMENT_REQUESTED';
                        final isOpen = n.actionState == 'OPEN';
                        final settlementId = n.payload?['settlementId'] as String?;
                        final amountPaise = n.payload?['amountPaise'] as int? ?? 0;

                        return Dismissible(
                          key: Key('notif_${n.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: colors.accentOwe.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            alignment: Alignment.centerRight,
                            child: Icon(Icons.delete_outline_rounded, color: colors.accentOwe),
                          ),
                          onDismissed: (_) {
                            ref.read(notificationsNotifierProvider.notifier).deleteNotification(n.id);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: n.isRead ? colors.surfaceFlat : colors.glassFillStrong,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isOpen
                                    ? colors.accentBrass
                                    : (n.isRead ? colors.divider : colors.accentReceive.withValues(alpha: 0.4)),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      isActionable
                                          ? Icons.account_balance_wallet_outlined
                                          : (n.type.contains('FRIEND')
                                              ? Icons.person_add_rounded
                                              : Icons.receipt_long_rounded),
                                      color: isOpen
                                          ? colors.accentBrass
                                          : (n.isRead ? colors.textMuted : colors.accentReceive),
                                      size: 24,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(n.title, style: SplitUpTypography.title(color: colors.textPrimary)),
                                              ),
                                              if (!n.isRead)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  margin: const EdgeInsets.only(top: 4, left: 6, right: 6),
                                                  decoration: BoxDecoration(
                                                    color: colors.accentReceive,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              IconButton(
                                                icon: Icon(Icons.close_rounded, size: 16, color: colors.textMuted.withValues(alpha: 0.7)),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                                                tooltip: 'Dismiss',
                                                onPressed: () {
                                                  ref.read(notificationsNotifierProvider.notifier).deleteNotification(n.id);
                                                },
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(n.body, style: SplitUpTypography.body(color: colors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // Inline Confirm / Reject for Actionable Settlement Requests
                                if (isActionable && isOpen && settlementId != null) ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: colors.accentReceive,
                                            foregroundColor: Colors.black,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                          icon: const Icon(Icons.check_rounded, size: 16),
                                          label: const Text('Confirm'),
                                          onPressed: () async {
                                            try {
                                              await ref
                                                  .read(settlementsNotifierProvider.notifier)
                                                  .confirmSettlement(settlementId);
                                            } catch (_) {}
                                            await ref
                                                .read(notificationsNotifierProvider.notifier)
                                                .updateActionState(
                                                  n.id,
                                                  'DONE',
                                                  actionResult: 'CONFIRMED',
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Confirmed ${formatPaise(amountPaise)} settlement.')),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: colors.accentOwe,
                                            side: BorderSide(color: colors.accentOwe),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                          ),
                                          icon: const Icon(Icons.close_rounded, size: 16),
                                          label: const Text('Decline'),
                                          onPressed: () async {
                                            try {
                                              await ref
                                                  .read(settlementsNotifierProvider.notifier)
                                                  .rejectSettlement(settlementId);
                                            } catch (_) {}
                                            await ref
                                                .read(notificationsNotifierProvider.notifier)
                                                .updateActionState(
                                                  n.id,
                                                  'DONE',
                                                  actionResult: 'REJECTED',
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Settlement request declined.')),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                // Result state if acted upon
                                if (n.actionState == 'DONE') ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: (n.actionResult == 'CONFIRMED' ? colors.accentReceive : colors.accentOwe)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      n.actionResult == 'CONFIRMED'
                                          ? 'You confirmed this settlement'
                                          : 'You declined this settlement',
                                      style: SplitUpTypography.caption(
                                        color: n.actionResult == 'CONFIRMED' ? colors.accentReceive : colors.accentOwe,
                                      ).copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
