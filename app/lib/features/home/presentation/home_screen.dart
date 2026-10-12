import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../friends/data/friends_repository.dart';
import '../../friends/domain/friend_model.dart';
import '../../friends/presentation/add_friend_sheet.dart';
import '../../friends/presentation/select_friends_sheet.dart';
import '../../expenses/presentation/add_expense_screen.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../profile/data/user_profile_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final asyncFriends = ref.watch(friendsNotifierProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final userProfile = ref.watch(userProfileProvider);

    final friends = asyncFriends.maybeWhen(
      data: (items) => items,
      orElse: () => <FriendModel>[],
    );

    // Calculate totals
    int totalOwedToMe = 0;
    int totalIOwe = 0;
    for (final f in friends) {
      if (f.netPaise > 0) totalOwedToMe += f.netPaise;
      if (f.netPaise < 0) totalIOwe += f.netPaise.abs();
    }
    final netBalance = totalOwedToMe - totalIOwe;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: colors.accentReceive,
            backgroundColor: colors.surfaceFlatRaised,
            onRefresh: () async {
              ref.invalidate(friendsNotifierProvider);
              await Future.delayed(const Duration(milliseconds: 350));
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                // Top Bar with Notifications Bell
                SliverToBoxAdapter(
                  child: FadeSlideEntrance(
                    offset: const Offset(0.0, -0.04),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const AppLogo.symbol(size: 30),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SplitUp',
                                    style: SplitUpTypography.headline(color: colors.textPrimary),
                                  ),
                                  Text(
                                    'Hey, ${userProfile.name}',
                                    style: SplitUpTypography.label(color: colors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Stack(
                            children: [
                              IconButton(
                                icon: Icon(Icons.notifications_outlined, color: colors.textPrimary, size: 26),
                                onPressed: () => context.push('/notifications'),
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: colors.accentReceive,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      unreadCount > 9 ? '9+' : '$unreadCount',
                                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Hero Balance Card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: FadeSlideEntrance(
                      delay: const Duration(milliseconds: 80),
                      child: GlassCard(
                        strong: true,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TOTAL NET BALANCE',
                          style: SplitUpTypography.caption(color: colors.textMuted).copyWith(
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        MoneyText(
                          netBalance,
                          variant: MoneyVariant.display,
                          showSign: true,
                        ),
                        const SizedBox(height: 20),
                        Container(height: 1, color: colors.divider),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.arrow_downward_rounded, size: 14, color: colors.accentReceive),
                                      const SizedBox(width: 4),
                                      Text(
                                        'You are owed',
                                        style: SplitUpTypography.label(color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  MoneyText(
                                    totalOwedToMe,
                                    variant: MoneyVariant.body,
                                    customColor: colors.accentReceive,
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 36, color: colors.divider),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.arrow_upward_rounded, size: 14, color: colors.accentOwe),
                                      const SizedBox(width: 4),
                                      Text(
                                        'You owe',
                                        style: SplitUpTypography.label(color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  MoneyText(
                                    totalIOwe,
                                    variant: MoneyVariant.body,
                                    customColor: colors.accentOwe,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

              // Friends Ledger Header with Add Friend Action
              SliverToBoxAdapter(
                child: FadeSlideEntrance(
                  delay: const Duration(milliseconds: 120),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Friends',
                              style: SplitUpTypography.title(color: colors.textPrimary),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${friends.length})',
                              style: SplitUpTypography.label(color: colors.textMuted),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colors.accentReceive,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                          onPressed: () => AddFriendSheet.show(context),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Add Friend'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Friends List or Empty State
              if (asyncFriends.isLoading && friends.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: SplitUpSkeletonList(count: 4),
                  ),
                )
              else if (friends.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: EmptyState(
                        icon: Icons.group_add_outlined,
                        title: 'No friends added yet',
                        message: 'Add friends to easily split expenses, calculate balances, and settle dues.',
                        action: PrimaryButton(
                          label: 'Add your first friend',
                          icon: Icons.person_add_rounded,
                          onPressed: () => AddFriendSheet.show(context),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = friends[index];
                        final isOwe = item.netPaise < 0;

                        return FadeSlideEntrance(
                          delay: Duration(milliseconds: 140 + (index < 6 ? index * 35 : 210)),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: colors.surfaceFlat,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: colors.divider),
                            ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => context.push('/friend/${item.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Avatar(
                                    name: item.resolvedName,
                                    size: 46,
                                    isPlaceholder: !item.isAppUser,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                item.resolvedName,
                                                style: SplitUpTypography.title(color: colors.textPrimary).copyWith(
                                                  fontSize: 16,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (!item.isAppUser) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: colors.statusWarn.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  'SMS',
                                                  style: TextStyle(fontSize: 10, color: colors.statusWarn, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.phoneE164,
                                          style: SplitUpTypography.caption(color: colors.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      MoneyText(
                                        item.netPaise,
                                        variant: MoneyVariant.body,
                                        showSign: true,
                                      ),
                                      if (isOwe) ...[
                                        const SizedBox(height: 6),
                                        SettleButton(
                                          amountPaise: item.netPaise.abs(),
                                          compact: true,
                                          onPressed: () => context.push('/friend/${item.id}'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                      childCount: friends.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        ),
      ),
    ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () async {
          final selectedFriends = await SelectFriendsSheet.show(context);
          if (selectedFriends != null && selectedFriends.isNotEmpty && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => AddExpenseScreen(
                  friendIds: selectedFriends.map((f) => f.id).toList(),
                  initialMembers: [
                    {'id': 'usr_arhaam', 'name': 'You', 'isMe': true},
                    ...selectedFriends.map((f) => {
                          'id': f.id,
                          'name': f.resolvedName,
                          'isMe': false,
                        }),
                  ],
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.add_rounded, size: 24),
        label: Text(
          'Add Expense',
          style: SplitUpTypography.title(color: Colors.white).copyWith(fontSize: 15),
        ),
      ),
    );
  }
}
