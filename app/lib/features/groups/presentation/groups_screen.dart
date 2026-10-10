import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/money/paise.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../data/groups_repository.dart';

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final asyncGroups = ref.watch(groupsNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Groups',
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
          child: asyncGroups.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: SplitUpLoadingAnimation(message: 'Loading groups...'),
              ),
            ),
            error: (err, _) => Center(
              child: Text('Error loading groups: $err', style: TextStyle(color: colors.accentOwe)),
            ),
            data: (groups) {
              if (groups.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_outlined, size: 64, color: colors.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        'No groups yet',
                        style: SplitUpTypography.title(color: colors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Create a group for your flatmates or friends',
                        style: SplitUpTypography.caption(color: colors.textMuted),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: colors.accentReceive,
                backgroundColor: colors.surfaceFlatRaised,
                onRefresh: () async {
                  ref.invalidate(groupsNotifierProvider);
                  await Future.delayed(const Duration(milliseconds: 350));
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: groups.length + 1,
                  itemBuilder: (context, index) {
                    if (index == groups.length) {
                      return const SizedBox(height: 100);
                    }

                    final group = groups[index];
                    final isOwe = group.myNetPaise < 0;

                    return FadeSlideEntrance(
                      delay: Duration(milliseconds: 50 * index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: colors.surfaceFlat,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.divider),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => context.push('/groups/${group.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: colors.accentBrass.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: colors.glassBorder),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(Icons.group_rounded, color: colors.accentBrass, size: 26),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            group.name,
                                            style: SplitUpTypography.title(color: colors.textPrimary).copyWith(fontSize: 17),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${group.members.length} members · Total spend: ${formatPaise(group.totalSpentPaise)}',
                                            style: SplitUpTypography.caption(color: colors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isOwe ? 'You owe' : (group.myNetPaise > 0 ? 'You get' : 'Settled'),
                                          style: SplitUpTypography.caption(color: colors.textMuted),
                                        ),
                                        const SizedBox(height: 2),
                                        MoneyText(
                                          group.myNetPaise,
                                          variant: MoneyVariant.body,
                                          showSign: true,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(height: 1, color: colors.divider),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        group.lastActivity,
                                        style: SplitUpTypography.caption(color: colors.textSecondary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(Icons.arrow_forward_ios_rounded, size: 12, color: colors.textMuted),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => context.push('/groups/create'),
        icon: const Icon(Icons.group_add_rounded, size: 22),
        label: Text(
          'Create Group',
          style: SplitUpTypography.title(color: Colors.white).copyWith(fontSize: 15),
        ),
      ),
    );
  }
}
