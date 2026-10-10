import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

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
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: EmptyState(icon: Icons.notifications_off_outlined, title: 'No notifications', message: 'You are all caught up!'));
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final n = items[index];
                  return InkWell(
                    onTap: () => ref.read(notificationsNotifierProvider.notifier).markRead(n.id),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: n.isRead ? colors.surfaceFlat : colors.glassFillStrong,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: n.isRead ? colors.divider : colors.accentReceive.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            n.type == 'FRIEND_ADDED' || n.type == 'FRIEND_JOINED'
                                ? Icons.person_add_rounded
                                : Icons.receipt_long_rounded,
                            color: n.isRead ? colors.textMuted : colors.accentReceive,
                            size: 24,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title, style: SplitUpTypography.title(color: colors.textPrimary)),
                                const SizedBox(height: 4),
                                Text(n.body, style: SplitUpTypography.body(color: colors.textSecondary)),
                              ],
                            ),
                          ),
                          if (!n.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(color: colors.accentReceive, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    ),
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
