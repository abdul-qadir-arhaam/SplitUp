import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/mock/mock_data.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final friends = MockDataRepository.friends;

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
          child: CustomScrollView(
            slivers: [
              // Top Bar with Notifications Bell
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SplitUp',
                            style: SplitUpTypography.headline(color: colors.textPrimary),
                          ),
                          Text(
                            'Hey, ${MockDataRepository.currentUser.name}',
                            style: SplitUpTypography.label(color: colors.textSecondary),
                          ),
                        ],
                      ),
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications_outlined, color: colors.textPrimary, size: 26),
                            onPressed: () => context.push('/notifications'),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: colors.statusWarn,
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.bgBase, width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Hero Balance Card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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

              // Friends Ledger Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Friends',
                        style: SplitUpTypography.title(color: colors.textPrimary),
                      ),
                      Text(
                        '${friends.length} friends',
                        style: SplitUpTypography.label(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),

              // Friends List
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = friends[index];
                      final isOwe = item.netPaise < 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceFlat,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: colors.divider),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => context.push('/friend/${item.user.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Avatar(
                                  name: item.user.displayName,
                                  size: 46,
                                  isPlaceholder: item.user.isPlaceholder,
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
                                              item.user.displayName,
                                              style: SplitUpTypography.title(color: colors.textPrimary).copyWith(
                                                fontSize: 16,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (item.user.isPlaceholder) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              'SMS',
                                              style: SplitUpTypography.caption(color: colors.textMuted),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.lastActivity ?? 'No recent activity',
                                        style: SplitUpTypography.label(color: colors.textMuted),
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
                                        onPressed: () => context.push('/friend/${item.user.id}'),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.accentReceive,
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () => context.push('/add-expense'),
        icon: const Icon(Icons.add_rounded, size: 24),
        label: Text(
          'Add Expense',
          style: SplitUpTypography.title(color: Colors.white).copyWith(fontSize: 15),
        ),
      ),
    );
  }
}
